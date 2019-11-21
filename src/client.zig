const std = @import("std");
const os = std.os;
const Allocator = std.mem.Allocator;
const RESP3 = @import("./parser.zig").RESP3Parser;
const ArgSerializer = @import("./serializer.zig").ArgSerializer;

pub const Client = struct {
    broken: bool = false,
    fd: os.fd_t,
    sock: std.fs.File,
    sock_addr: os.sockaddr,
    in: std.fs.File.InStream,
    out: std.fs.File.OutStream,
    bufin: InBuff,
    bufout: OutBuff,
    inlock: if (std.io.is_async) std.event.Lock else void,
    outlock: if (std.io.is_async) std.event.Lock else void,

    const Self = @This();
    const InBuff = std.io.BufferedInStream(std.fs.File.InStream.Error);
    const OutBuff = std.io.BufferedOutStream(std.fs.File.OutStream.Error);

    pub fn initIp4(self: *Self, addr: []const u8, port: u16) !void {
        self.fd = try os.socket(os.AF_INET, os.SOCK_STREAM, 0);
        errdefer os.close(self.fd);

        self.sock_addr = (try std.net.Address.parseIp4(addr, port)).any;
        try os.connect(self.fd, &self.sock_addr, @sizeOf(os.sockaddr_in));

        self.sock = std.fs.File.openHandle(self.fd);
        self.in = self.sock.inStream();
        self.out = self.sock.outStream();
        self.bufin = InBuff.init(&self.in.stream);
        self.bufout = OutBuff.init(&self.out.stream);

        if (std.io.is_async) {
            self.inlock = std.event.Lock.init();
            self.outlock = std.event.Lock.init();
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
        if (self.broken) return error.BrokenConnection;
        errdefer self.broken = true;

        var heldIn: std.event.Lock.Held = undefined;
        var heldOut: std.event.Lock.Held = undefined;
        var heldOutFrame: @Frame(std.event.Lock.acquire) = undefined;

        // If we're doing async/await we need to first grab the lock
        // for the input stream. Once we have it, we also need to queue
        // for the output lock, but we don't have to acquire it fully yet.
        // For this reason we don't await `self.outlock.acquire()` and in
        // the meantime we start writing to the input stream.
        if (std.io.is_async) {
            heldIn = self.inlock.acquire();
            heldOutFrame = async self.outlock.acquire();
        }

        var heldOutFrameNotAwaited = true;
        defer if (std.io.is_async and heldOutFrameNotAwaited) {
            heldOut = await heldOutFrame;
            heldOut.release();
        };

        {
            // We add a block to release the input lock before we start
            // reading from the output stream.
            defer if (std.io.is_async) heldIn.release();

            // try ArgSerializer.serialize(&self.out.stream, args);
            try ArgSerializer.serializeCommand(&self.bufout.stream, args);
            try self.bufout.flush();
        }

        if (std.io.is_async) {
            heldOutFrameNotAwaited = false;
            heldOut = await heldOutFrame;
        }
        defer if (std.io.is_async) heldOut.release();

        return RESP3.parse(T, &self.bufin.stream);
    }

    pub fn sendAlloc(self: *Self, comptime T: type, allocator: *Allocator, args: var) !T {
        if (self.broken) return error.BrokenConnection;
        errdefer self.broken = true;

        var heldIn: std.event.Lock.Held = undefined;
        var heldOut: std.event.Lock.Held = undefined;
        var heldOutFrame: @Frame(std.event.Lock.acquire) = undefined;

        // If we're doing async/await we need to first grab the lock
        // for the input stream. Once we have it, we also need to queue
        // for the output lock, but we don't have to acquire it fully yet.
        // For this reason we don't await `self.outlock.acquire()` and in
        // the meantime we start writing to the input stream.
        if (std.io.is_async) {
            heldIn = self.inlock.acquire();
            heldOutFrame = async self.outlock.acquire();
        }

        var heldOutFrameNotAwaited = true;
        defer if (std.io.is_async and heldOutFrameNotAwaited) {
            heldOut = await heldOutFrame;
            heldOut.release();
        };

        {
            // We add a block to release the input lock before we start
            // reading from the output stream.
            defer if (std.io.is_async) heldIn.release();

            // try ArgSerializer.serialize(&self.out.stream, args);
            try ArgSerializer.serializeCommand(&self.bufout.stream, args);
            try self.bufout.flush();
        }

        if (std.io.is_async) {
            heldOutFrameNotAwaited = false;
            heldOut = await heldOutFrame;
        }
        defer if (std.io.is_async) heldOut.release();

        return RESP3.parseAlloc(T, allocator, &self.bufin.stream);
    }
};
