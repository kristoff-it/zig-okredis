const std = @import("std");
const os = std.os;
const net = std.net;
const Allocator = std.mem.Allocator;
const RESP3 = @import("./parser.zig").RESP3Parser;
const CommandSerializer = @import("./serializer.zig").CommandSerializer;
const OrErr = @import("./types/error.zig").OrErr;

pub const Buffering = union(enum) {
    NoBuffering,
    Fixed: usize,
};

pub const Logging = union(enum) {
    NoLogging,
    Logging,
};

pub const Client = RedisClient(.NoBuffering, .NoLogging);
pub const BufferedClient = RedisClient(.{ .Fixed = 4096 }, .NoLogging);
pub fn RedisClient(comptime buffering: Buffering, comptime _: Logging) type {
    const ReadBuffer = switch (buffering) {
        .NoBuffering => void,
        .Fixed => |b| std.io.BufferedReader(b, net.Stream.Reader),
    };

    const WriteBuffer = switch (buffering) {
        .NoBuffering => void,
        .Fixed => |b| std.io.BufferedWriter(b, net.Stream.Writer),
    };

    return struct {
        conn: net.Stream,
        reader: switch (buffering) {
            .NoBuffering => net.Stream.Reader,
            .Fixed => ReadBuffer.Reader,
        },
        writer: switch (buffering) {
            .NoBuffering => net.Stream.Writer,
            .Fixed => WriteBuffer.Writer,
        },
        readBuffer: ReadBuffer,
        writeBuffer: WriteBuffer,

        readLock: if (std.io.is_async) std.event.Lock else void,
        writeLock: if (std.io.is_async) std.event.Lock else void,

        // Connection state
        broken: bool = false,

        const Self = @This();

        /// Initializes a Client on a connection / pipe provided by the user.
        pub fn init(self: *Self, conn: net.Stream) !void {
            self.conn = conn;
            switch (buffering) {
                .NoBuffering => {
                    self.reader = conn.reader();
                    self.writer = conn.writer();
                },
                .Fixed => {
                    self.readBuffer = ReadBuffer{ .unbuffered_reader = conn.reader() };
                    self.reader = self.readBuffer.reader();
                    self.writeBuffer = WriteBuffer{ .unbuffered_writer = conn.writer() };
                    self.writer = self.writeBuffer.writer();
                },
            }

            if (std.io.is_async) {
                self.readLock = std.event.Lock{};
                self.writeLock = std.event.Lock{};
            }

            self.broken = false;

            self.send(void, .{ "HELLO", "3" }) catch |err| {
                self.broken = true;
                if (err == error.GotErrorReply) {
                    return error.ServerTooOld;
                } else {
                    return err;
                }
            };
        }

        pub fn close(self: Self) void {
            self.conn.close();
        }

        /// Sends a command to Redis and tries to parse the response as the specified type.
        pub fn send(self: *Self, comptime T: type, cmd: anytype) !T {
            return self.pipelineImpl(T, cmd, .{ .one = {} });
        }

        /// Like `send`, can allocate memory.
        pub fn sendAlloc(self: *Self, comptime T: type, allocator: Allocator, cmd: anytype) !T {
            return self.pipelineImpl(T, cmd, .{ .one = {}, .ptr = allocator });
        }

        /// Performs a Redis MULTI/EXEC transaction using pipelining.
        /// It's mostly provided for convenience as the same result
        /// can be achieved by making explicit use of `pipe` and `pipeAlloc`.
        pub fn trans(self: *Self, comptime Ts: type, cmds: anytype) !Ts {
            return self.transactionImpl(Ts, cmds, .{});
        }

        /// Like `trans`, but can allocate memory.
        pub fn transAlloc(self: *Self, comptime Ts: type, allocator: Allocator, cmds: anytype) !Ts {
            return transactionImpl(self, Ts, cmds, .{ .ptr = allocator });
        }

        fn transactionImpl(self: *Self, comptime Ts: type, cmds: anytype, allocator: anytype) !Ts {
            // TODO: this is not threadsafe.
            _ = try self.send(void, .{"MULTI"});

            try self.pipe(void, cmds);

            if (@hasField(@TypeOf(allocator), "ptr")) {
                return self.sendAlloc(Ts, allocator.ptr, .{"EXEC"});
            } else {
                return self.send(Ts, .{"EXEC"});
            }
        }

        /// Sends a group of commands more efficiently than sending them one by one.
        pub fn pipe(self: *Self, comptime Ts: type, cmds: anytype) !Ts {
            return pipelineImpl(self, Ts, cmds, .{});
        }

        /// Like `pipe`, but can allocate memory.
        pub fn pipeAlloc(self: *Self, comptime Ts: type, allocator: Allocator, cmds: anytype) !Ts {
            return pipelineImpl(self, Ts, cmds, .{ .ptr = allocator });
        }

        fn pipelineImpl(self: *Self, comptime Ts: type, cmds: anytype, allocator: anytype) !Ts {
            // TODO: find a way to express some of the metaprogramming requirements
            // in a more clear way. Using @hasField this way is ugly.
            {
                // if (self.broken) return error.BrokenConnection;
                // errdefer self.broken = true;
            }
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
                    try CommandSerializer.serializeCommand(self.writer, cmds);
                } else {
                    inline for (std.meta.fields(@TypeOf(cmds))) |field| {
                        const cmd = @field(cmds, field.name);
                        // try ArgSerializer.serialize(&self.out.stream, args);
                        try CommandSerializer.serializeCommand(self.writer, cmd);
                    }
                } // Here is where the write lock gets released by the `defer` statement.

                if (buffering == .Fixed) {
                    if (std.io.is_async) {
                        // TODO: see if this stuff can be implemented nicely
                        // so that you don't have to depend on magic numbers & implementation details.
                        self.writeLock.mutex.lock();
                        defer self.writeLock.mutex.unlock();
                        if (self.writeLock.head == 1) {
                            try self.writeBuffer.flush();
                        }
                    } else {
                        try self.writeBuffer.flush();
                    }
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
                    return RESP3.parseAlloc(Ts, allocator.ptr, self.reader);
                } else {
                    return RESP3.parse(Ts, self.reader);
                }
            } else {
                var result: Ts = undefined;

                if (Ts == void) {
                    const cmd_num = std.meta.fields(@TypeOf(cmds)).len;
                    comptime var i: usize = 0;
                    inline while (i < cmd_num) : (i += 1) {
                        try RESP3.parse(void, self.reader);
                    }
                    return;
                } else {
                    switch (@typeInfo(Ts)) {
                        .Struct => {
                            inline for (std.meta.fields(Ts)) |field| {
                                if (@hasField(@TypeOf(allocator), "ptr")) {
                                    @field(result, field.name) = try RESP3.parseAlloc(field.field_type, allocator.ptr, self.reader);
                                } else {
                                    @field(result, field.name) = try RESP3.parse(field.field_type, self.reader);
                                }
                            }
                        },
                        .Array => {
                            var i: usize = 0;
                            while (i < Ts.len) : (i += 1) {
                                if (@hasField(@TypeOf(allocator), "ptr")) {
                                    result[i] = try RESP3.parseAlloc(Ts.Child, allocator.ptr, self.reader);
                                } else {
                                    result[i] = try RESP3.parse(Ts.Child, self.reader);
                                }
                            }
                        },
                        .Pointer => |ptr| {
                            switch (ptr.size) {
                                .One => {
                                    if (@hasField(@TypeOf(allocator), "ptr")) {
                                        result = try RESP3.parseAlloc(Ts, allocator.ptr, self.reader);
                                    } else {
                                        result = try RESP3.parse(Ts, self.reader);
                                    }
                                },
                                .Many => {
                                    if (@hasField(@TypeOf(allocator), "ptr")) {
                                        result = try allocator.alloc(ptr.child, ptr.size);
                                        errdefer allocator.free(result);

                                        for (result) |*elem| {
                                            elem.* = try RESP3.parseAlloc(Ts.Child, allocator.ptr, self.reader);
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
}

test "docs" {
    @import("std").testing.refAllDecls(Client);
}
