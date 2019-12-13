const std = @import("std");
const os = std.os;
const Allocator = std.mem.Allocator;
const RESP3 = @import("./parser.zig").RESP3Parser;
const CommandSerializer = @import("./serializer.zig").CommandSerializer;
const OrErr = @import("./types/error.zig").OrErr;

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

    const Self = @This();
    const InBuff = std.io.BufferedInStream(std.fs.File.InStream.Error);
    const OutBuff = std.io.BufferedOutStream(std.fs.File.OutStream.Error);

    pub fn initIp4(self: *Self, addr: []const u8, port: u16) !void {
        self.fd = try os.socket(os.AF_INET, os.SOCK_STREAM, 0);
        errdefer os.close(self.fd);

        self.sock_addr = (try std.net.Address.parseIp4(addr, port)).any;
        try os.connect(self.fd, &self.sock_addr, @sizeOf(os.sockaddr_in));

        self.sock = std.fs.File.openHandle(self.fd);
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
            error.GotErrorReply => @panic("Sorry, heyredis is RESP3 only and requires a Redis server built from the unstable branch."),
        };
    }

    pub fn close(self: Self) void {
        os.close(self.fd);
    }

    pub fn send(self: *Self, comptime T: type, args: var) !T {
        return sendImpl(self, T, args, .{});
    }

    pub fn sendAlloc(self: *Self, comptime T: type, allocator: *Allocator, args: var) !T {
        return sendImpl(self, T, args, .{ .ptr = allocator });
    }

    fn sendImpl(self: *Client, comptime T: type, args: var, comptime allocator: var) !T {
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

            // try ArgSerializer.serialize(&self.out.stream, args);
            try CommandSerializer.serializeCommand(&self.bufWriteStream.stream, args);

            // Flush only if we don't have any other frame waiting.
            // if (@atomicLoad(u8, &self.writeLock.queue_empty_bit, .SeqCst) == 1) {
            if (std.io.is_async) {
                if (self.writeLock.queue.head == null) {
                    try self.bufWriteStream.flush();
                } else {
                    std.debug.warn("skipping\n");
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
        if (@hasDecl(@TypeOf(allocator), "ptr")) {
            return RESP3.parseAlloc(T, allocator.ptr, &self.bufReadStream.stream);
        } else {
            return RESP3.parse(T, &self.bufReadStream.stream);
        }
    }

    pub fn transaction(self: *Client, comptime Ts: type, cmds: var) !Ts {
        return transactionImpl(self, Ts, cmds, .{});
    }

    pub fn transactionAlloc(self: *Client, comptime Ts: type, allocator: *Allocator, cmds: var) !Ts {
        return transactionImpl(self, Ts, cmds, .{ .ptr = allocator });
    }

    fn transactionImpl(self: *Client, comptime Ts: type, cmds: var, allocator: var) !Ts {
        // TODO: type checks, error checks, make it efficient.
        //       (i.e., write a real implementation lmao)
        //       Right now we are reusing the code in .send,
        //       but we are not doing any pipelining.
        _ = try self.send(OrErr(void), .{"MULTI"});

        inline for (std.meta.fields(@TypeOf(cmds))) |field| {
            const cmd = @field(cmds, field.name);
            _ = try self.send(OrErr(void), cmd);
        }

        if (@hasDecl(@TypeOf(allocator), "ptr")) {
            return self.sendAlloc(Ts, allocator.ptr, .{"EXEC"});
        } else {
            return self.send(Ts, .{"EXEC"});
        }
    }
};
