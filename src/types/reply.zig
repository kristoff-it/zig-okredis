const std = @import("std");
const Reader = std.Io.Reader;
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Verbatim = @import("./verbatim.zig").Verbatim;

pub const E = error.DynamicReplyError;

/// DynamicReply lets you parse Redis replies without having to to know
/// their shape beforehand. It also supports parsing Redis errors and
/// attributes. By using DynamicReply you will be able to parse any possible
/// Redis reply. It even supports non-toplevel errors.
pub const DynamicReply = struct {
    attribs: [][2]*DynamicReply,
    data: Data,

    pub const Data = union(enum) {
        Nil: void,
        Bool: bool,
        Number: i64,
        Double: f64,
        Bignum: std.math.big.int.Managed,
        String: Verbatim,
        List: []DynamicReply,
        Set: []DynamicReply,
        Map: [][2]*DynamicReply,
    };

    pub const Redis = struct {
        pub const Parser = struct {
            pub const HandlesAttributes = true;

            pub fn parse(_: u8, comptime _: type, _: anytype) !DynamicReply {
                @compileError("DynamicReply requires an allocator. Use `sendAlloc`!");
            }

            pub fn destroy(
                self: DynamicReply,
                comptime rootParser: type,
                allocator: Allocator,
            ) void {
                rootParser.freeReply(self.attribs, allocator);
                switch (self.data) {
                    .Nil, .Bool, .Number, .Double => {},
                    .Bignum => {
                        // `std.math.bit.Init` wants the parameter to be writable
                        // so we have to copy it inside a `var` variable.
                        var x = self;
                        x.data.Bignum.deinit();
                    },
                    .String => |ver| rootParser.freeReply(ver, allocator),
                    .List, .Set => |lst| {
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

            pub fn parseAlloc(
                tag: u8,
                comptime rootParser: type,
                allocator: Allocator,
                r: *Reader,
            ) error{DynamicReplyError}!DynamicReply {
                var itemTag = tag;

                var res: DynamicReply = undefined;
                if (itemTag == '|') {
                    // Here we lie to the root parser and claim we encountered a map type >:3

                    // No error catching is done because DynamicReply parses correctly
                    // both errors and nil values.
                    res.attribs = rootParser.parseAllocFromTag([][2]*DynamicReply, '%', allocator, r) catch return E;
                    itemTag = r.takeByte() catch return E;
                } else {
                    res.attribs = &[0][2]*DynamicReply{};
                }

                res.data = switch (itemTag) {
                    else => return E,
                    '_' => .{ .Nil = {} },
                    '#' => .{
                        .Bool = rootParser.parseFromTag(bool, '#', r) catch return E,
                    },
                    ':' => .{
                        .Number = rootParser.parseFromTag(i64, ':', r) catch return E,
                    },
                    ',' => .{
                        .Double = rootParser.parseFromTag(f64, ',', r) catch return E,
                    },
                    '+', '$', '=' => .{
                        .String = rootParser.parseAllocFromTag(Verbatim, itemTag, allocator, r) catch return E,
                    },
                    '%' => .{
                        .Map = rootParser.parseAllocFromTag([][2]*DynamicReply, '%', allocator, r) catch return E,
                    },
                    '*' => .{
                        .List = rootParser.parseAllocFromTag([]DynamicReply, '*', allocator, r) catch return E,
                    },
                    '~' => .{
                        .Set = rootParser.parseAllocFromTag([]DynamicReply, '~', allocator, r) catch return E,
                    },
                    '(' => .{
                        .Bignum = rootParser.parseAllocFromTag(std.math.big.int.Managed, '(', allocator, r) catch return E,
                    },
                };

                return res;
            }
        };
    };
};

test "dynamic replies" {
    const parser = @import("../parser.zig").RESP3Parser;
    const allocator = std.heap.page_allocator;

    {
        var simple_string = MakeSimpleString();
        const reply = try DynamicReply.Redis.Parser.parseAlloc(
            '+',
            parser,
            allocator,
            &simple_string,
        );
        try testing.expectEqualSlices(u8, "Yayyyy I'm a string!", reply.data.String.string);
    }

    {
        var complex_list = MakeComplexList();
        const reply = try DynamicReply.Redis.Parser.parseAlloc(
            '*',
            parser,
            allocator,
            &complex_list,
        );
        try testing.expectEqual(@as(usize, 0), reply.attribs.len);

        try testing.expectEqualSlices(u8, "Hello", reply.data.List[0].data.String.string);

        try testing.expectEqual(true, reply.data.List[1].data.Bool);
        try testing.expectEqual(@as(usize, 0), reply.data.List[1].attribs.len);

        try testing.expectEqual(@as(usize, 0), reply.data.List[2].attribs.len);

        try testing.expectEqual(@as(i64, 123), reply.data.List[2].data.List[0].data.Number);
        try testing.expectEqual(@as(usize, 0), reply.data.List[2].data.List[0].attribs.len);

        try testing.expectEqual(@as(f64, 12.34), reply.data.List[2].data.List[1].data.Double);
        try testing.expectEqual(@as(usize, 0), reply.data.List[2].data.List[1].attribs.len);
    }

    {
        var cmplx_set = MakeComplexListWithAttributes();
        const reply = try DynamicReply.Redis.Parser.parseAlloc(
            '|',
            parser,
            allocator,
            &cmplx_set,
        );
        try testing.expectEqual(@as(usize, 2), reply.attribs.len);
        try testing.expectEqualSlices(
            u8,
            "Ciao",
            reply.attribs[0][0].data.String.string,
        );
        try testing.expectEqualSlices(
            u8,
            "World",
            reply.attribs[0][1].data.String.string,
        );
        try testing.expectEqualSlices(
            u8,
            "Peach",
            reply.attribs[1][0].data.String.string,
        );
        try testing.expectEqual(@as(f64, 9.99), reply.attribs[1][1].data.Double);

        try testing.expectEqualSlices(
            u8,
            "Hello",
            reply.data.List[0].data.String.string,
        );
        try testing.expectEqual(@as(usize, 0), reply.data.List[0].attribs.len);

        try testing.expectEqual(true, reply.data.List[1].data.Bool);
        try testing.expectEqual(@as(usize, 1), reply.data.List[1].attribs.len);
        try testing.expectEqualSlices(
            u8,
            "ttl",
            reply.data.List[1].attribs[0][0].data.String.string,
        );
        try testing.expectEqual(
            @as(i64, 100),
            reply.data.List[1].attribs[0][1].data.Number,
        );

        try testing.expectEqual(@as(usize, 0), reply.data.List[2].attribs.len);

        try testing.expectEqual(
            @as(i64, 123),
            reply.data.List[2].data.List[0].data.Number,
        );
        try testing.expectEqual(
            @as(usize, 1),
            reply.data.List[2].data.List[0].attribs.len,
        );
        try testing.expectEqualSlices(
            u8,
            "Banana",
            reply.data.List[2].data.List[0].attribs[0][0].data.String.string,
        );
        try testing.expectEqual(
            true,
            reply.data.List[2].data.List[0].attribs[0][1].data.Bool,
        );

        try testing.expectEqual(
            @as(i64, 424242),
            try reply.data.List[2].data.List[1].data.Bignum.toInt(i64),
        );
        try testing.expectEqual(
            @as(usize, 0),
            reply.data.List[2].data.List[1].attribs.len,
        );

        try testing.expectEqual(
            @as(f64, 12.34),
            reply.data.List[2].data.List[2].data.Double,
        );
        try testing.expectEqual(
            @as(usize, 0),
            reply.data.List[2].data.List[2].attribs.len,
        );
    }
}

fn MakeSimpleString() Reader {
    return std.Io.Reader.fixed("+Yayyyy I'm a string!\r\n"[1..]);
}
fn MakeComplexList() Reader {
    return std.Io.Reader.fixed(
        "*3\r\n+Hello\r\n#t\r\n*2\r\n:123\r\n,12.34\r\n"[1..],
    );
}

// zig fmt: off
fn MakeComplexListWithAttributes() Reader {
    return std.Io.Reader.fixed(
        ("|2\r\n" ++
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
            "*3\r\n" ++
                "|1\r\n" ++
                    "+Banana\r\n" ++
                    "#t\r\n" ++
                ":123\r\n" ++
                "(424242\r\n" ++
                ",12.34\r\n")
    [1..]);
}
// zig fmt: on

test "docs" {
    @import("std").testing.refAllDecls(DynamicReply);
}
