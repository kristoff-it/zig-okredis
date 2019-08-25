const std = @import("std");
const os = std.os;
const Allocator = std.mem.Allocator;
const RESP3 = @import("./parser.zig").RESP3Parser;
const ArgSerializer = @import("./serializer.zig").ArgSerializer;

pub const Client = struct {
    broken: bool = false,
    fd: os.fd_t,
    sock: std.fs.File,
    in: std.fs.File.InStream,
    out: std.fs.File.OutStream,
    bufin: InBuff,
    bufout: OutBuff,

    const Self = @This();
    const InBuff = std.io.BufferedInStream(std.fs.File.InStream.Error);
    const OutBuff = std.io.BufferedOutStream(std.fs.File.OutStream.Error);

    pub fn initIp4(addr: []const u8, port: u16) !Self {
        const sockfd = try os.socket(os.AF_INET, os.SOCK_STREAM, 0);
        errdefer os.close(sockfd);

        var sock_addr = os.sockaddr{ .in = undefined };
        sock_addr.in.family = os.AF_INET;
        sock_addr.in.port = std.mem.nativeToBig(u16, port);
        sock_addr.in.addr = try std.net.parseIp4(addr);
        sock_addr.in.zero = [_]u8{0} ** 8;

        try os.connect(sockfd, &sock_addr, @sizeOf(os.sockaddr_in));

        var new: Self = undefined;
        new.broken = false;
        new.fd = sockfd;
        new.sock = std.fs.File.openHandle(sockfd);
        new.in = new.sock.inStream();
        new.out = new.sock.outStream();
        new.bufin = InBuff.init(&new.in.stream);
        new.bufout = OutBuff.init(&new.out.stream);

        try new.out.stream.write("*2\r\n$5\r\nHELLO\r\n$1\r\n3\r\n");
        RESP3.parse(void, &new.in.stream) catch |err| switch (err) {
            else => return err,
            error.GotErrorReply => @panic("Sorry, heyredis is RESP3 only and requires a Redis server built from the unstable branch."),
        };

        return new;
    }

    pub fn close(self: Self) void {
        os.close(self.fd);
    }

    pub fn send(self: *Self, comptime T: type, args: ...) !T {
        if (self.broken) return error.BrokenConnection;
        errdefer self.broken = true;

        try ArgSerializer.serialize(&self.out.stream, args);
        return RESP3.parse(T, &self.in.stream);
    }

    pub fn sendAlloc(self: *Self, comptime T: type, allocator: *Allocator, args: ...) !T {
        if (self.broken) return error.BrokenConnection;
        errdefer self.broken = true;

        try ArgSerializer.serialize(&self.out.stream, args);
        return RESP3.parseAlloc(T, allocator, &self.in.stream);
    }
};
