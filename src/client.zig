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

    const Self = @This();
    const InBuff = std.io.BufferedInStream(std.fs.File.InStream.Error);
    const OutBuff = std.io.BufferedOutStream(std.fs.File.OutStream.Error);

    pub fn initIp4(self: *Self, addr: []const u8, port: u16) !void {
        self.fd = try os.socket(os.AF_INET, os.SOCK_STREAM, 0);
        errdefer os.close(self.fd);

        self.sock_addr = os.sockaddr{ .in = undefined };
        self.sock_addr.in.family = os.AF_INET;
        self.sock_addr.in.port = std.mem.nativeToBig(u16, port);
        self.sock_addr.in.addr = try std.net.parseIp4(addr);
        self.sock_addr.in.zero = [_]u8{0} ** 8;

        try os.connect(self.fd, &self.sock_addr, @sizeOf(os.sockaddr_in));

        self.sock = std.fs.File.openHandle(self.fd);
        self.in = self.sock.inStream();
        self.out = self.sock.outStream();
        self.bufin = InBuff.init(&self.in.stream);
        self.bufout = OutBuff.init(&self.out.stream);

        // try self.out.stream.write("*2\r\n$5\r\nHELLO\r\n$1\r\n3\r\n");
        try self.bufout.stream.write("*2\r\n$5\r\nHELLO\r\n$1\r\n3\r\n");
        try self.bufout.flush();
        RESP3.parse(void, &self.bufin.stream) catch |err| switch (err) {
            else => return err,
            error.GotErrorReply => @panic("Sorry, heyredis is RESP3 only and requires a Redis server built from the unstable branch."),
        };
    }

    pub fn close(self: Self) void {
        os.close(self.fd);
    }

    pub fn send(self: *Self, comptime T: type, args: ...) !T {
        if (self.broken) return error.BrokenConnection;
        errdefer self.broken = true;

        // try ArgSerializer.serialize(&self.out.stream, args);
        try ArgSerializer.serialize(&self.bufout.stream, args);
        try self.bufout.flush();
        return RESP3.parse(T, &self.bufin.stream);
    }

    pub fn sendAlloc(self: *Self, comptime T: type, allocator: *Allocator, args: ...) !T {
        if (self.broken) return error.BrokenConnection;
        errdefer self.broken = true;

        // try ArgSerializer.serialize(&self.out.stream, args);
        try ArgSerializer.serialize(&self.bufout.stream, args);
        try self.bufout.flush();
        return RESP3.parseAlloc(T, allocator, &self.bufin.stream);
    }
};
