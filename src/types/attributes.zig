const std = @import("std");
const Allocator = std.mem.Allocator;
const FixBuf = @import("./fixbuf.zig").FixBuf;
const DynamicReply = @import("./reply.zig").DynamicReply;
const testing = std.testing;

/// A generic type that can capture attributes from a Redis reply.
pub fn WithAttribs(comptime T: type) type {
    return struct {
        /// Attributes are stored as an array of key-value pairs.
        /// Each element of a pair is a DynamicReply.
        attribs: [][2]DynamicReply,
        data: T,

        const Self = @This();
        pub const Redis = struct {
            pub const Parser = struct {
                pub const HandlesAttributes = true;

                pub fn parse(_: u8, comptime _: type, _: anytype) !Self {
                    @compileError("WithAttribs requires an allocator. Use `sendAlloc`.");
                }

                pub fn destroy(self: Self, comptime rootParser: type, allocator: Allocator) void {
                    rootParser.freeReply(self.attribs, allocator);
                    rootParser.freeReply(self.data, allocator);
                }

                pub fn parseAlloc(tag: u8, comptime rootParser: type, allocator: Allocator, msg: anytype) !Self {
                    var itemTag = tag;

                    var res: Self = undefined;
                    if (itemTag == '|') {
                        // Here we lie to the root parser and claim we encountered a map type,
                        // otherwise the parser would also try to parse the actual reply along
                        // side the attribute.

                        // No error catching is done because DynamicReply parses correctly
                        // both errors and nil values, and it can't incur in a DecodingError.
                        res.attribs = try rootParser.parseAllocFromTag(
                            [][2]DynamicReply,
                            '%',
                            allocator,
                            msg,
                        );
                        itemTag = try msg.readByte();
                    } else {
                        res.attribs = &[0][2]DynamicReply{};
                    }

                    res.data = try rootParser.parseAllocFromTag(T, itemTag, allocator, msg);
                    return res;
                }
            };
        };
    };
}

test "WithAttribs" {
    const parser = @import("../parser.zig").RESP3Parser;
    const allocator = std.heap.page_allocator;

    const res = try parser.parseAlloc(
        WithAttribs([2]WithAttribs([]WithAttribs(i64))),
        allocator,
        MakeComplexListWithAttributes().reader(),
    );
    try testing.expectEqual(@as(usize, 2), res.attribs.len);
    try testing.expectEqualSlices(u8, "Ciao", res.attribs[0][0].data.String.string);
    try testing.expectEqualSlices(u8, "World", res.attribs[0][1].data.String.string);
    try testing.expectEqualSlices(u8, "Peach", res.attribs[1][0].data.String.string);
    try testing.expectEqual(@as(f64, 9.99), res.attribs[1][1].data.Double);

    try testing.expectEqual(@as(usize, 0), res.data[0].data[0].attribs.len);
    try testing.expectEqual(@as(i64, 20), res.data[0].data[0].data);

    try testing.expectEqual(@as(usize, 1), res.data[0].data[1].attribs.len);
    try testing.expectEqualSlices(u8, "ttl", res.data[0].data[1].attribs[0][0].data.String.string);
    try testing.expectEqual(@as(i64, 128), res.data[0].data[1].attribs[0][1].data.Number);
    try testing.expectEqual(@as(i64, 100), res.data[0].data[1].data);

    try testing.expectEqual(@as(usize, 0), res.data[1].attribs.len);
    try testing.expectEqual(@as(usize, 1), res.data[1].data[0].attribs.len);
    try testing.expectEqualSlices(u8, "Banana", res.data[1].data[0].attribs[0][0].data.String.string);
    try testing.expectEqual(true, res.data[1].data[0].attribs[0][1].data.Bool);
    try testing.expectEqual(@as(i64, 123), res.data[1].data[0].data);

    try testing.expectEqual(@as(usize, 0), res.data[1].data[1].attribs.len);
    try testing.expectEqual(@as(i64, 99), res.data[1].data[1].data);
}
// zig fmt: off
fn MakeComplexListWithAttributes() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream((
        "|2\r\n" ++
            "+Ciao\r\n" ++
            "+World\r\n" ++
            "+Peach\r\n" ++
            ",9.99\r\n" ++
        "*2\r\n" ++
            "*2\r\n" ++
                ":20\r\n" ++
                "|1\r\n" ++
                    "+ttl\r\n" ++
                    ":128\r\n" ++
                ":100\r\n" ++
            "*2\r\n" ++
                "|1\r\n" ++
                    "+Banana\r\n" ++
                    "#t\r\n" ++
                ":123\r\n" ++
                ":99\r\n"
    )[0..]);
}
// zig fmt: on

test "docs" {
    @import("std").testing.refAllDecls(@This());
    @import("std").testing.refAllDecls(WithAttribs(FixBuf(100)));
    @import("std").testing.refAllDecls(WithAttribs([]u8));
    @import("std").testing.refAllDecls(WithAttribs(usize));
}
