const std = @import("std");
const Reader = std.Io.Reader;
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
                pub fn parse(
                    tag: u8,
                    comptime rootParser: type,
                    r: *Reader,
                ) !Self {
                    switch (tag) {
                        else => return error.UnsupportedConversion,
                        '-', '!' => {
                            try rootParser.parseFromTag(void, tag, r);
                            return error.GotErrorReply;
                        },
                        '+', '(' => {
                            var res: Self = undefined;
                            var ch = try r.takeByte();
                            for (&res.buf, 0..) |*elem, i| {
                                if (ch == '\r') {
                                    res.len = i;
                                    try r.discardAll(1);
                                    return res;
                                }
                                elem.* = ch;
                                ch = try r.takeByte();
                            }
                            if (ch != '\r') return error.BufTooSmall;
                            try r.discardAll(1);
                            return res;
                        },
                        '$' => {
                            const digits = try r.takeSentinel('\r');
                            const respSize = try fmt.parseInt(usize, digits, 10);
                            try r.discardAll(1);

                            if (respSize > size) return error.BufTooSmall;

                            var res: Self = undefined;
                            res.len = respSize;
                            try r.readSliceAll(res.buf[0..respSize]);
                            try r.discardAll(2);

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
