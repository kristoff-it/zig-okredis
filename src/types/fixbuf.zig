const std = @import("std");
const fmt = std.fmt;

/// It's a fixed length buffer, useful for parsing strings
/// without requiring an allocator.
pub fn FixBuf(comptime size: usize) type {
    return struct {
        buf: [size]u8,
        len: usize,

        const Self = @This();

        /// Returns a slice pointing to the contents in the buffer.
        pub fn toSlice(self: *const Self) []const u8 {
            return self.buf[0..self.len];
        }

        pub const Redis = struct {
            pub const Parser = struct {
                pub fn parse(tag: u8, comptime rootParser: type, msg: anytype) !Self {
                    switch (tag) {
                        else => return error.UnsupportedConversion,
                        '-', '!' => {
                            try rootParser.parseFromTag(void, tag, msg);
                            return error.GotErrorReply;
                        },
                        '+', '(' => {
                            var res: Self = undefined;
                            var ch = try msg.readByte();
                            for (res.buf) |*elem, i| {
                                if (ch == '\r') {
                                    res.len = i;
                                    try msg.skipBytes(1, .{});
                                    return res;
                                }
                                elem.* = ch;
                                ch = try msg.readByte();
                            }
                            if (ch != '\r') return error.BufTooSmall;
                            try msg.skipBytes(1, .{});
                            return res;
                        },
                        '$' => {
                            // TODO: write real implementation
                            var buf: [100]u8 = undefined;
                            var end: usize = 0;
                            for (buf) |*elem, i| {
                                const ch = try msg.readByte();
                                elem.* = ch;
                                if (ch == '\r') {
                                    end = i;
                                    break;
                                }
                            }

                            try msg.skipBytes(1, .{});
                            const respSize = try fmt.parseInt(usize, buf[0..end], 10);

                            if (respSize > size) return error.BufTooSmall;

                            var res: Self = undefined;
                            res.len = respSize;
                            _ = try msg.readNoEof(res.buf[0..respSize]);
                            try msg.skipBytes(2, .{});
                            return res;
                        },
                    }
                }

                pub fn destroy(_: Self, comptime _: type, _: std.mem.Allocator) void {}

                pub fn parseAlloc(tag: u8, comptime rootParser: type, msg: anytype) !Self {
                    return parse(tag, rootParser, msg);
                }
            };
        };
    };
}

test "docs" {
    @import("std").testing.refAllDecls(@This());
    @import("std").testing.refAllDecls(FixBuf(42));
}
