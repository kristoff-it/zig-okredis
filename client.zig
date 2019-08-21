const std = @import("std");
const os = std.os;

const RESP3 = @import("./parser.zig").RESP3Parser;

pub const Client = struct {
    in: std.fs.File.InStream,
    out: std.fs.File.OutStream,

    const Self = @This();
    pub fn initIp4(addr: []const u8, port: u16) !Self {
        const sockfd = try os.socket(os.AF_INET, os.SOCK_STREAM, 0);
        errdefer os.close(sockfd);

        var sock_addr = os.sockaddr{
            .in = os.sockaddr_in{
                .len = 0,
                .family = os.AF_INET,
                .port = std.mem.nativeToBig(u16, port),
                .addr = try std.net.parseIp4(addr),
                .zero = [_]u8{0} ** 8,
            },
        };

        try os.connect(sockfd, &sock_addr, @sizeOf(os.sockaddr_in));
        var sock = std.fs.File.openHandle(sockfd);

        var new: Self = undefined;
        new.in = sock.inStream();
        new.out = sock.outStream();

        try new.out.stream.write("HELLO 3\r\n");
        try RESP3.parse(void, &new.in.stream);

        return new;
    }

    pub fn send(self: *Self, comptime T: type, command: []const u8) !T {
        try self.out.stream.write(command);
        try self.out.stream.write("\r\n");
        return RESP3.parse(T, &self.in.stream);
    }
};
