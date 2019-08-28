const std = @import("std");
const Allocator = std.mem.Allocator;
const KV = @import("./kv.zig").KV;
const DynamicReply = @import("./reply.zig").DynamicReply;
const testing = std.testing;

/// A generic type that can capture attributes from a reply
pub fn WithAttribs(comptime T: type) type {
    return struct {
        attribs: []KV(DynamicReply, DynamicReply),
        data: T,

        const Self = @This();
        pub const Redis = struct {
            pub const Parser = struct {
                pub const HandlesAttributes = true;

                pub fn parse(tag: u8, comptime rootParser: type, msg: var) !Self {
                    @compileError("WithAttribs requires an allocator. Use `sendAlloc`.");
                }

                pub fn destroy(self: Self, comptime rootParser: type, allocator: *Allocator) void {
                    rootParser.freeReply(attribs, allocator);
                    rootParser.freeReply(data, allocator);
                }

                pub fn parseAlloc(tag: u8, comptime rootParser: type, allocator: *Allocator, msg: var) !Self {
                    var itemTag = tag;

                    var res: Self = undefined;
                    if (itemTag == '|') {
                        // Here we lie to the root parser and claim we encountered a map type >:3
                        res.attribs = try rootParser.parseAllocFromTag([]KV(DynamicReply, DynamicReply), '%', allocator, msg);
                        itemTag = try msg.readByte();
                    } else {
                        res.attribs = [0]KV(DynamicReply, DynamicReply){};
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
    const allocator = std.heap.direct_allocator;

    const res = try parser.parseAlloc(WithAttribs([2]WithAttribs([]WithAttribs(i64))), allocator, &MakeComplexListWithAttributes().stream);
    testing.expectEqual(usize(2), res.attribs.len);
    testing.expectEqualSlices(u8, "Ciao", res.attribs[0].key.data.String);
    testing.expectEqualSlices(u8, "World", res.attribs[0].value.data.String);
    testing.expectEqualSlices(u8, "Peach", res.attribs[1].key.data.String);
    testing.expectEqual(f64(9.99), res.attribs[1].value.data.Double);

    testing.expectEqual(usize(0), res.data[0].data[0].attribs.len);
    testing.expectEqual(i64(20), res.data[0].data[0].data);

    testing.expectEqual(usize(1), res.data[0].data[1].attribs.len);
    testing.expectEqualSlices(u8, "ttl", res.data[0].data[1].attribs[0].key.data.String);
    testing.expectEqual(i64(128), res.data[0].data[1].attribs[0].value.data.Number);
    testing.expectEqual(i64(100), res.data[0].data[1].data);

    testing.expectEqual(usize(0), res.data[1].attribs.len);
    testing.expectEqual(usize(1), res.data[1].data[0].attribs.len);
    testing.expectEqualSlices(u8, "Banana", res.data[1].data[0].attribs[0].key.data.String);
    testing.expectEqual(true, res.data[1].data[0].attribs[0].value.data.Bool);
    testing.expectEqual(i64(123), res.data[1].data[0].data);

    testing.expectEqual(usize(0), res.data[1].data[1].attribs.len);
    testing.expectEqual(i64(99), res.data[1].data[1].data);
}
//zig fmt: off
fn MakeComplexListWithAttributes() std.io.SliceInStream {
    return std.io.SliceInStream.init(
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
    [0..]);
}
//zig fmt: on
