const std = @import("std");
const Allocator = std.mem.Allocator;
const KV = @import("./kv.zig").KV;
const testing = std.testing;

pub const E = error.DynamicReplyError;

/// DynamicReply is a tagged union that lets you
/// parse Redis replies without having to
/// to know their shape beforehand.
/// It also supports parsing Redis errors,
/// in case you are dealing with a whacky
/// module that likes to nest errors inside
/// a normal reply.
pub const DynamicReply = union(enum) {
    Nil: void,
    Bool: bool,
    Number: i64,
    Double: f64,
    String: []u8,
    Map: []KV(DynamicReply, DynamicReply),
    List: []DynamicReply,
    // Set: std.AutoHash(Reply, void),

    pub const Redis = struct {
        pub const Parser = struct {
            pub fn parse(tag: u8, comptime _: type, msg: var) !DynamicReply {
                @compileError("Redis Reply objects require an allocator. Use `sendAlloc`!");
            }

            pub fn destroy(self: DynamicReply, comptime rootParser: type, allocator: *Allocator) void {
                switch (self) {
                    .Nil, .Bool, .Number, .Double => {},
                    .String => |str| allocator.free(str),
                    .List => |lst| {
                        for (lst) |elem| destroy(elem, rootParser, allocator);
                        allocator.free(lst);
                    },
                    .Map => |map| {
                        // rootParser.freeReply(map, allocator);
                        for (map) |elem| rootParser.freeReply(elem, allocator);
                        allocator.free(map);
                    },
                }
            }

            pub fn parseAlloc(tag: u8, comptime rootParser: type, allocator: *Allocator, msg: var) error{DynamicReplyError}!DynamicReply {
                return switch (tag) {
                    else => return E,
                    '_' => DynamicReply{ .Nil = {} },
                    '#' => DynamicReply{ .Bool = rootParser.parseFromTag(bool, '#', msg) catch return E },
                    ':' => DynamicReply{ .Number = rootParser.parseFromTag(i64, ':', msg) catch return E },
                    ',' => DynamicReply{ .Double = rootParser.parseFromTag(f64, ',', msg) catch return E },
                    '$' => DynamicReply{ .String = rootParser.parseAllocFromTag([]u8, '$', allocator, msg) catch return E },
                    '+' => DynamicReply{ .String = rootParser.parseAllocFromTag([]u8, '+', allocator, msg) catch return E },
                    '%' => DynamicReply{ .Map = rootParser.parseAllocFromTag([]KV(DynamicReply, DynamicReply), '%', allocator, msg) catch return E },
                    '*' => DynamicReply{ .List = rootParser.parseAllocFromTag([]DynamicReply, '*', allocator, msg) catch return E },
                };
            }
        };
    };
};

test "dynamic replies" {
    const parser = @import("../parser.zig").RESP3Parser;
    const allocator = std.heap.direct_allocator;

    {
        const reply = try DynamicReply.Redis.Parser.parseAlloc('+', parser, allocator, &MakeSimpleString().stream);
        testing.expectEqualSlices(u8, "Yayyyy I'm a string!", reply.String);
    }

    {
        const reply = try DynamicReply.Redis.Parser.parseAlloc('*', parser, allocator, &MakeComplexList().stream);
        testing.expectEqualSlices(u8, "Hello", reply.List[0].String);
        testing.expectEqual(true, reply.List[1].Bool);

        testing.expectEqual(i64(123), reply.List[2].List[0].Number);
        testing.expectEqual(f64(12.34), reply.List[2].List[1].Double);
    }
}

fn MakeSimpleString() std.io.SliceInStream {
    return std.io.SliceInStream.init("Yayyyy I'm a string!\r\n"[0..]);
}
fn MakeComplexList() std.io.SliceInStream {
    return std.io.SliceInStream.init("3\r\n+Hello\r\n#t\r\n*2\r\n:123\r\n,12.34\r\n"[0..]);
}
