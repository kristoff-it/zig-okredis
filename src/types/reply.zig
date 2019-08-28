const std = @import("std");
const Allocator = std.mem.Allocator;
const KV = @import("./kv.zig").KV;
const Verbatim = @import("./verbatim.zig").Verbatim;
const testing = std.testing;

pub const E = error.DynamicReplyError;

/// DynamicReply lets you parse Redis replies without having to to know
/// their shape beforehand. It also supports parsing Redis errors and
/// attributes. By using DynamicReply you will be able to parse any possible
/// Redis reply. It even supports non-toplevel errors.
pub const DynamicReply = struct {
    attribs: []KV(DynamicReply, DynamicReply),
    data: Data,

    const Data = union(enum) {
        Nil: void,
        Bool: bool,
        Number: i64,
        Double: f64,
        String: []u8,
        Verbatim: Verbatim,
        Map: []KV(DynamicReply, DynamicReply),
        List: []DynamicReply,
        // Set: std.AutoHash(Reply, void),
    };

    pub const Redis = struct {
        pub const Parser = struct {
            pub const HandlesAttributes = true;
            pub fn parse(tag: u8, comptime _: type, msg: var) !DynamicReply {
                @compileError("DynamicReply require an allocator. Use `sendAlloc`!");
            }

            pub fn destroy(self: DynamicReply, comptime rootParser: type, allocator: *Allocator) void {
                rootParser.freeReply(self.attribs, allocator);
                switch (self.data) {
                    .Nil, .Bool, .Number, .Double => {},
                    .String => |str| allocator.free(str),
                    .Verbatim => |ver| rootParser.freeReply(ver, allocator),
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
                var itemTag = tag;

                var res: DynamicReply = undefined;
                if (itemTag == '|') {
                    // Here we lie to the root parser and claim we encountered a map type >:3
                    res.attribs = rootParser.parseAllocFromTag([]KV(DynamicReply, DynamicReply), '%', allocator, msg) catch return E;
                    itemTag = msg.readByte() catch return E;
                } else {
                    res.attribs = [0]KV(DynamicReply, DynamicReply){};
                }

                res.data = switch (itemTag) {
                    else => return E,
                    '_' => Data{ .Nil = {} },
                    '#' => Data{ .Bool = rootParser.parseFromTag(bool, '#', msg) catch return E },
                    ':' => Data{ .Number = rootParser.parseFromTag(i64, ':', msg) catch return E },
                    ',' => Data{ .Double = rootParser.parseFromTag(f64, ',', msg) catch return E },
                    '$' => Data{ .String = rootParser.parseAllocFromTag([]u8, '$', allocator, msg) catch return E },
                    '=' => Data{ .Verbatim = rootParser.parseAllocFromTag(Verbatim, '=', allocator, msg) catch return E },
                    '+' => Data{ .String = rootParser.parseAllocFromTag([]u8, '+', allocator, msg) catch return E },
                    '%' => Data{ .Map = rootParser.parseAllocFromTag([]KV(DynamicReply, DynamicReply), '%', allocator, msg) catch return E },
                    '*' => Data{ .List = rootParser.parseAllocFromTag([]DynamicReply, '*', allocator, msg) catch return E },
                };

                return res;
            }
        };
    };
};

test "dynamic replies" {
    const parser = @import("../parser.zig").RESP3Parser;
    const allocator = std.heap.direct_allocator;

    {
        const reply = try DynamicReply.Redis.Parser.parseAlloc('+', parser, allocator, &MakeSimpleString().stream);
        testing.expectEqualSlices(u8, "Yayyyy I'm a string!", reply.data.String);
    }

    {
        const reply = try DynamicReply.Redis.Parser.parseAlloc('*', parser, allocator, &MakeComplexList().stream);
        testing.expectEqual(usize(0), reply.attribs.len);

        testing.expectEqualSlices(u8, "Hello", reply.data.List[0].data.String);

        testing.expectEqual(true, reply.data.List[1].data.Bool);
        testing.expectEqual(usize(0), reply.data.List[1].attribs.len);

        testing.expectEqual(usize(0), reply.data.List[2].attribs.len);

        testing.expectEqual(i64(123), reply.data.List[2].data.List[0].data.Number);
        testing.expectEqual(usize(0), reply.data.List[2].data.List[0].attribs.len);

        testing.expectEqual(f64(12.34), reply.data.List[2].data.List[1].data.Double);
        testing.expectEqual(usize(0), reply.data.List[2].data.List[1].attribs.len);
    }

    {
        const reply = try DynamicReply.Redis.Parser.parseAlloc('|', parser, allocator, &MakeComplexListWithAttributes().stream);
        testing.expectEqual(usize(2), reply.attribs.len);
        testing.expectEqualSlices(u8, "Ciao", reply.attribs[0].key.data.String);
        testing.expectEqualSlices(u8, "World", reply.attribs[0].value.data.String);
        testing.expectEqualSlices(u8, "Peach", reply.attribs[1].key.data.String);
        testing.expectEqual(f64(9.99), reply.attribs[1].value.data.Double);

        testing.expectEqualSlices(u8, "Hello", reply.data.List[0].data.String);
        testing.expectEqual(usize(0), reply.data.List[0].attribs.len);

        testing.expectEqual(true, reply.data.List[1].data.Bool);
        testing.expectEqual(usize(1), reply.data.List[1].attribs.len);
        testing.expectEqualSlices(u8, "ttl", reply.data.List[1].attribs[0].key.data.String);
        testing.expectEqual(i64(100), reply.data.List[1].attribs[0].value.data.Number);

        testing.expectEqual(usize(0), reply.data.List[2].attribs.len);

        testing.expectEqual(i64(123), reply.data.List[2].data.List[0].data.Number);
        testing.expectEqual(usize(1), reply.data.List[2].data.List[0].attribs.len);
        testing.expectEqualSlices(u8, "Banana", reply.data.List[2].data.List[0].attribs[0].key.data.String);
        testing.expectEqual(true, reply.data.List[2].data.List[0].attribs[0].value.data.Bool);

        testing.expectEqual(f64(12.34), reply.data.List[2].data.List[1].data.Double);
        testing.expectEqual(usize(0), reply.data.List[2].data.List[1].attribs.len);
    }
}

fn MakeSimpleString() std.io.SliceInStream {
    return std.io.SliceInStream.init("Yayyyy I'm a string!\r\n"[0..]);
}
fn MakeComplexList() std.io.SliceInStream {
    return std.io.SliceInStream.init("3\r\n+Hello\r\n#t\r\n*2\r\n:123\r\n,12.34\r\n"[0..]);
}

//zig fmt: off
fn MakeComplexListWithAttributes() std.io.SliceInStream {
    return std.io.SliceInStream.init(
        "2\r\n" ++
            "+Ciao\r\n" ++
            "+World\r\n" ++
            "+Peach\r\n" ++
            ",9.99\r\n" ++
        "*3\r\n" ++
            "+Hello\r\n" ++
            "|1\r\n" ++
                "+ttl\r\n" ++
                ":100\r\n" ++ 
            "#t\r\n" ++
            "*2\r\n" ++
                "|1\r\n" ++
                    "+Banana\r\n" ++
                    "#t\r\n" ++ 
                ":123\r\n" ++
                ",12.34\r\n"
    [0..]);
}
//zig fmt: on
