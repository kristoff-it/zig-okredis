const std = @import("std");
const Allocator = std.mem.Allocator;
const KV = @import("./kv.zig").KV;
const testing = std.testing;

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
    Map: []KV(Self, Self),
    List: []Self,
    // Set: std.AutoHash(Reply, void),

    const Self = @This();
    pub const Redis = struct {
        pub const Parser = struct {
            pub fn parse(tag: u8, comptime _: type, msg: var) !Self {
                @compileError("Redis Reply objects require an allocator. Use `sendAlloc`!");
            }

            pub fn destroy(self: Self, comptime rootParser: type, allocator: *Allocator) void {
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

            pub fn parseAlloc(tag: u8, comptime rootParser: type, allocator: *Allocator, msg: var) anyerror!Self {
                return switch (tag) {
                    else => return error.ProtocolError,
                    '_' => Self{ .Nil = {} },
                    '#' => Self{ .Bool = try rootParser.parseFromTag(bool, '#', msg) },
                    ':' => Self{ .Number = try rootParser.parseFromTag(i64, ':', msg) },
                    ',' => Self{ .Double = try rootParser.parseFromTag(f64, ',', msg) },
                    '$' => Self{ .String = try rootParser.parseAllocFromTag([]u8, '$', allocator, msg) },
                    '+' => Self{ .String = try rootParser.parseAllocFromTag([]u8, '+', allocator, msg) },
                    '%' => Self{ .Map = try rootParser.parseAllocFromTag([]KV(Self, Self), '%', allocator, msg) },
                    '*' => Self{ .List = try rootParser.parseAllocFromTag([]Self, '*', allocator, msg) },
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
