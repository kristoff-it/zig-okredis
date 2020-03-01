const std = @import("std");
const os = std.os;
const net = std.net;
const Allocator = std.mem.Allocator;
const RESP3 = @import("./parser.zig").RESP3Parser;
const CommandSerializer = @import("./serializer.zig").CommandSerializer;
const OrErr = @import("./types/error.zig").OrErr;

/// Struct representing a Redis client
pub const Client = struct {
    broken: bool = false,
    fd: os.fd_t,
    sock: std.fs.File,
    sock_addr: os.sockaddr,
    readStream: std.fs.File.InStream,
    writeStream: std.fs.File.OutStream,
    bufReadStream: InBuff,
    bufWriteStream: OutBuff,
    readLock: if (std.io.is_async) std.event.Lock else void,
    writeLock: if (std.io.is_async) std.event.Lock else void,

    const InBuff = std.io.BufferedInStream(std.fs.File.InStream.Error);
    const OutBuff = std.io.BufferedOutStream(std.fs.File.OutStream.Error);

    /// Initializes a Client and connects it to the specified IPv4 address and port.
    pub fn initIp4(self: *Client, addr: []const u8, port: u16) !void {
        // self.sock = try net.tcpConnectToAddress(try net.Address.parseIp4(addr, port));
        errdefer self.sock.close();

        self.readStream = self.sock.inStream();
        self.writeStream = self.sock.outStream();
        self.bufReadStream = InBuff.init(&self.readStream.stream);
        self.bufWriteStream = OutBuff.init(&self.writeStream.stream);

        if (std.io.is_async) {
            self.readLock = std.event.Lock.init();
            self.writeLock = std.event.Lock.init();
        }

        self.send(void, .{ "HELLO", "3" }) catch |err| switch (err) {
            else => return err,
            error.GotErrorReply => @panic("Sorry, okredis is RESP3 only and requires a Redis 6+ server."),
        };
    }

    pub fn close(self: Client) void {
        self.sock.close();
    }

    /// Sends a command to Redis and tries to parse the response as the specified type.
    pub fn send(self: *Client, comptime T: type, cmd: var) !T {
        return self.pipelineImpl(T, cmd, .{ .one = {} });
    }

    /// Like `send`, can allocate memory.
    pub fn sendAlloc(self: *Client, comptime T: type, allocator: *Allocator, cmd: var) !T {
        return self.pipelineImpl(T, cmd, .{ .one = {}, .ptr = allocator });
    }

    /// Performs a Redis MULTI/EXEC transaction using pipelining.
    /// It's mostly provided for convenience as the same result
    /// can be achieved by making explicit use of `pipe` and `pipeAlloc`.
    pub fn trans(self: *Client, comptime Ts: type, cmds: var) !Ts {
        return self.transactionImpl(Ts, cmds, .{});
    }

    /// Like `trans`, but can allocate memory.
    pub fn transAlloc(self: *Client, comptime Ts: type, allocator: *Allocator, cmds: var) !Ts {
        return transactionImpl(self, Ts, cmds, .{ .ptr = allocator });
    }

    fn transactionImpl(self: *Client, comptime Ts: type, cmds: var, allocator: var) !Ts {
        // TODO: this is not threadsafe.
        _ = try self.send(void, .{"MULTI"});

        const len = comptime std.meta.fields(@TypeOf(cmds)).len;
        try self.pipe(void, cmds);

        if (@hasField(@TypeOf(allocator), "ptr")) {
            return self.sendAlloc(Ts, allocator.ptr, .{"EXEC"});
        } else {
            return self.send(Ts, .{"EXEC"});
        }
    }

    /// Sends a group of commands more efficiently than sending them one by one.
    pub fn pipe(self: *Client, comptime Ts: type, cmds: var) !Ts {
        return pipelineImpl(self, Ts, cmds, .{});
    }

    /// Like `pipe`, but can allocate memory.
    pub fn pipeAlloc(self: *Client, comptime Ts: type, allocator: *Allocator, cmds: var) !Ts {
        return pipelineImpl(self, Ts, cmds, .{ .ptr = allocator });
    }

    fn pipelineImpl(self: *Client, comptime Ts: type, cmds: var, allocator: var) !Ts {
        // TODO: find a way to express some of the metaprogramming requirements
        // in a more clear way. Using @hasField this way is ugly.
        if (self.broken) return error.BrokenConnection;
        errdefer self.broken = true;

        var heldWrite: std.event.Lock.Held = undefined;
        var heldRead: std.event.Lock.Held = undefined;
        var heldReadFrame: @Frame(std.event.Lock.acquire) = undefined;

        // If we're doing async/await we need to first grab the lock
        // for the write stream. Once we have it, we also need to queue
        // for the read lock, but we don't have to acquire it fully yet.
        // For this reason we don't await `self.readLock.acquire()` and in
        // the meantime we start writing to the write stream.
        if (std.io.is_async) {
            heldWrite = self.writeLock.acquire();
            heldReadFrame = async self.readLock.acquire();
        }

        var heldReadFrameNotAwaited = true;
        defer if (std.io.is_async and heldReadFrameNotAwaited) {
            heldRead = await heldReadFrame;
            heldRead.release();
        };

        {
            // We add a block to release the write lock before we start
            // reading from the read stream.
            defer if (std.io.is_async) heldWrite.release();

            // Serialize all the commands
            if (@hasField(@TypeOf(allocator), "one")) {
                try CommandSerializer.serializeCommand(&self.bufWriteStream.stream, cmds);
            } else {
                inline for (std.meta.fields(@TypeOf(cmds))) |field| {
                    const cmd = @field(cmds, field.name);
                    // try ArgSerializer.serialize(&self.out.stream, args);
                    try CommandSerializer.serializeCommand(&self.bufWriteStream.stream, cmd);
                }
            } // Here is where the write lock gets released by the `defer` statement.

            // TODO: Flush only if we don't have any other frame waiting.
            // if (@atomicLoad(u8, &self.writeLock.queue_empty_bit, .SeqCst) == 1) {
            if (std.io.is_async) {
                if (self.writeLock.queue.head == null) {
                    try self.bufWriteStream.flush();
                }
            } else {
                try self.bufWriteStream.flush();
            }
        }

        if (std.io.is_async) {
            heldReadFrameNotAwaited = false;
            heldRead = await heldReadFrame;
        }
        defer if (std.io.is_async) heldRead.release();

        // TODO: error procedure
        if (@hasField(@TypeOf(allocator), "one")) {
            if (@hasField(@TypeOf(allocator), "ptr")) {
                return RESP3.parseAlloc(Ts, allocator.ptr, &self.bufReadStream.stream);
            } else {
                return RESP3.parse(Ts, &self.bufReadStream.stream);
            }
        } else {
            var result: Ts = undefined;

            if (Ts == void) {
                const cmd_num = std.meta.fields(@TypeOf(cmds)).len;
                comptime var i: usize = 0;
                inline while (i < cmd_num) : (i += 1) {
                    try RESP3.parse(void, &self.bufReadStream.stream);
                }
                return;
            } else {
                switch (@typeInfo(Ts)) {
                    .Struct => {
                        inline for (std.meta.fields(Ts)) |field| {
                            if (@hasField(@TypeOf(allocator), "ptr")) {
                                @field(result, field.name) = try RESP3.parseAlloc(field.field_type, allocator.ptr, &self.bufReadStream.stream);
                            } else {
                                @field(result, field.name) = try RESP3.parse(field.field_type, &self.bufReadStream.stream);
                            }
                        }
                    },
                    .Array => {
                        var i: usize = 0;
                        while (i < Ts.len) : (i += 1) {
                            if (@hasField(@TypeOf(allocator), "ptr")) {
                                result[i] = try RESP3.parseAlloc(Ts.Child, allocator.ptr, &self.bufReadStream.stream);
                            } else {
                                result[i] = try RESP3.parse(Ts.Child, &self.bufReadStream.stream);
                            }
                        }
                    },
                    .Pointer => |ptr| {
                        switch (ptr.size) {
                            .One => {
                                if (@hasField(@TypeOf(allocator), "ptr")) {
                                    result = try RESP3.parseAlloc(Ts, allocator.ptr, &self.bufReadStream.stream);
                                } else {
                                    result = try RESP3.parse(Ts, &self.bufReadStream.stream);
                                }
                            },
                            .Many => {
                                if (@hasField(@TypeOf(allocator), "ptr")) {
                                    result = try allocator.alloc(ptr.child, size);
                                    errdefer allocator.free(result);

                                    for (result) |*elem| {
                                        elem.* = try RESP3.parseAlloc(Ts.Child, allocator.ptr, &self.bufReadStream.stream);
                                    }
                                } else {
                                    @compileError("Use sendAlloc / pipeAlloc / transAlloc to decode pointer types.");
                                }
                            },
                        }
                    },
                    else => @compileError("Unsupported type"),
                }
            }
            return result;
        }
    }
};

test "docs" {
    @import("std").meta.refAllDecls(Client);
}
