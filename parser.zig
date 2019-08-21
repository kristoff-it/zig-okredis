const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;
const InStream = std.io.InStream;
const Allocator = std.mem.Allocator;

const BoolParser = @import("./t_bool.zig").BoolParser;
const BlobStringParser = @import("./t_string_blob.zig").BlobStringParser;
const SimpleStringParser = @import("./t_string_simple.zig").SimpleStringParser;
const FloatParser = @import("./t_float.zig").FloatParser;
const ListParser = @import("./t_list.zig").ListParser;
const MapParser = @import("./t_map.zig").MapParser;

pub const RESP3Parser = struct {
    const rootParser = @This();

    pub inline fn parse(comptime T: type, msg: var) !T {
        const tag = try msg.readByte();
        return parseFromTag(T, tag, msg);
    }

    pub fn parseFromTag(comptime T: type, tag: u8, msg: var) !T {
        comptime var RealType = T;
        switch (@typeInfo(T)) {
            .Pointer => @compileError("`parse` can't perform allocations so it can't handle pointers. Use `parseAlloc` instead."),
            .Optional => |opt| {
                RealType = opt.child;
                // Null micro-parser:
                if (tag == '_') {
                    try msg.skipBytes(2);
                    return null;
                }
            },
            else => {},
        }

        if ((@typeId(RealType) == .Struct or
            @typeId(RealType) == .Enum or
            @typeId(RealType) == .Union) and
            @hasDecl(RealType, "Redis"))
        {
            var res: T = try RealType.Redis.parse(tag, rootParser, msg);
            return res;
        } else {
            var res: T = switch (tag) {
                ',' => try ifSupported(FloatParser, RealType, msg),
                '#' => try ifSupported(BoolParser, RealType, msg),
                '$' => try ifSupported(BlobStringParser, RealType, msg),
                '+' => try ifSupported(SimpleStringParser, RealType, msg),
                '-', '!' => return error.UnexpectedErrorReply,
                '*' => try ifSupported(ListParser, RealType, msg),
                '%' => try ifSupported(MapParser, RealType, msg),
                // '_' => error.UnexpectedNilReply, // TODO: consider supporting it only for CRedisReply types!
                else => @panic("Encountered grave protocol error"),
            };
            return res;
        }
    }
    // TODO: if no parser supports the type conversion, @compileError!
    // The whole job of this function is to cut away calls to sub-parsers
    // if we know that the Zig type is not supported. This has both the benefit
    // of reducing code size and allows sub-parsers to @compileError when
    // the type requested is not supported.
    inline fn ifSupported(comptime parser: type, comptime T: type, msg: var) !T {
        return if (comptime parser.isSupported(T))
            parser.parse(T, rootParser, msg)
        else
            return error.UnsupportedConversion;
    }

    pub fn parseAlloc(comptime T: type, allocator: *Allocator, msg: var) !T {
        const tag = try msg.readByte();
        comptime var RealType = T;
        switch (@typeInfo(T)) {
            .Optional => |opt| {
                RealType = opt.child;
                // Null micro-parser:
                if (tag == '_') {
                    try msg.skipBytes(2);
                    return null;
                }
            },
            else => {},
        }

        comptime var InnerType = RealType;

        switch (@typeInfo(RealType)) {
            .Pointer => |ptr| {
                if (ptr.size == .Many) {
                    @compileError("Pointers to unknown size of elements " ++
                        "are not supported, use a slice or, for C-compatible strings, a c-pointer.");
                }
                InnerType = ptr.child;
            },
            else => {},
        }

        var res: T = if ((@typeId(RealType) == .Struct or
            @typeId(RealType) == .Enum or
            @typeId(RealType) == .Union) and
            @hasDecl(RealType, "Redis"))
            try RealType.parseAlloc(tag, rootParser, allocator, msg)
        else switch (tag) {
            ',' => try ifSupportedAlloc(FloatParser, RealType, allocator, msg),
            '#' => try ifSupportedAlloc(BoolParser, RealType, allocator, msg),
            '$' => try ifSupportedAlloc(BlobStringParser, RealType, allocator, msg),
            '+' => try ifSupportedAlloc(SimpleStringParser, RealType, allocator, msg),
            '-', '!' => return error.UnexpectedErrorReply,
            '*' => try ifSupportedAlloc(ListParser, RealType, allocator, msg),
            '%' => try ifSupportedAlloc(MapParser, RealType, allocator, msg),
            // '_' => error.NilButNoOptional, // TODO: consider supporting it only for CRedisReply types!
            else => @panic("Encountered grave protocol error"),
        };
        return res;
    }

    inline fn ifSupportedAlloc(comptime parser: type, comptime T: type, allocator: *Allocator, msg: var) !T {
        return if (comptime parser.isSupportedAlloc(T))
            parser.parseAlloc(T, rootParser, allocator, msg)
        else
            error.UnsupportedConversion;
    }
};

fn inArray(comptime T: type, slice: []const T, x: T) bool {
    for (slice) |elem| {
        if (elem == x) return true;
    }
    return false;
}

test "float" {

    // No alloc
    {
        var input = std.io.SliceInStream.init(",120.23\r\n"[0..]);
        const p1 = RESP3Parser.parse(f32, &input.stream) catch unreachable;
        testing.expect(p1 == 120.23);
    }

    //Alloc
    const allocator = std.heap.direct_allocator;
    {
        {
            const f = try RESP3Parser.parseAlloc(*f32, allocator, &Make1Float().stream);
            defer allocator.destroy(f);
            testing.expect(f.* == 120.23);
        }
        {
            const f = try RESP3Parser.parseAlloc([]f32, allocator, &Make2Float().stream);
            defer allocator.free(f);
            testing.expectEqualSlices(f32, [_]f32{ 1.1, 2.2 }, f);
        }
    }
}

fn Make1Float() std.io.SliceInStream {
    return std.io.SliceInStream.init(",120.23\r\n"[0..]);
}

fn Make2Float() std.io.SliceInStream {
    return std.io.SliceInStream.init("*2\r\n,1.1\r\n,2.2\r\n"[0..]);
}

test "optional" {
    const maybeInt: ?i64 = null;
    const maybeBool: ?bool = null;
    const maybeArr: ?[4]bool = null;
    testing.expectEqual(maybeInt, try RESP3Parser.parse(?i64, &MakeNull().stream));
    testing.expectEqual(maybeBool, try RESP3Parser.parse(?bool, &MakeNull().stream));
    testing.expectEqual(maybeArr, try RESP3Parser.parse(?[4]bool, &MakeNull().stream));
}
fn MakeNull() std.io.SliceInStream {
    return std.io.SliceInStream.init("_\r\n"[0..]);
}

test "array" {
    testing.expectError(error.LengthMismatch, RESP3Parser.parse([5]i64, &MakeArray().stream));
    testing.expectError(error.LengthMismatch, RESP3Parser.parse([0]i64, &MakeArray().stream));
    testing.expectError(error.UnsupportedConversion, RESP3Parser.parse([2]i64, &MakeArray().stream));
    testing.expectEqual([2]f32{ 1.2, 3.4 }, try RESP3Parser.parse([2]f32, &MakeArray().stream));
}
fn MakeArray() std.io.SliceInStream {
    return std.io.SliceInStream.init("*2\r\n,1.2\r\n,3.4\r\n"[0..]);
}

test "string" {
    testing.expectError(error.LengthMismatch, RESP3Parser.parse([5]u8, &MakeString().stream));
    testing.expectError(error.LengthMismatch, RESP3Parser.parse([2]u16, &MakeString().stream));
    testing.expectEqualSlices(u8, "Hello World!", try RESP3Parser.parse([12]u8, &MakeSimpleString().stream));
    testing.expectError(error.LengthMismatch, RESP3Parser.parse([11]u8, &MakeSimpleString().stream));
    testing.expectError(error.LengthMismatch, RESP3Parser.parse([13]u8, &MakeSimpleString().stream));

    const allocator = std.heap.direct_allocator;
    testing.expectEqualSlices(u8, "Banana", try RESP3Parser.parseAlloc([]u8, allocator, &MakeString().stream));
    testing.expectEqualSlices(u8, "Hello World!", try RESP3Parser.parseAlloc([]u8, allocator, &MakeSimpleString().stream));
}
fn MakeString() std.io.SliceInStream {
    return std.io.SliceInStream.init("$6\r\nBanana\r\n"[0..]);
}
fn MakeSimpleString() std.io.SliceInStream {
    return std.io.SliceInStream.init("+Hello World!\r\n"[0..]);
}

test "map2struct" {
    const RSB = @import("./types/string_buffer.zig").RedisStringBuffer;
    const MyStruct = struct {
        first: f32,
        second: bool,
        third: RSB(11),
    };

    const res = try RESP3Parser.parse(MyStruct, &MakeMap().stream);
    testing.expect(res.first == 12.34);
    testing.expect(res.second == true);
    testing.expectEqualSlices(u8, res.third.toSlice(), "Hello World");
}
test "hashmap" {
    const allocator = std.heap.direct_allocator;
    const FloatDict = std.AutoHashMap([3]u8, f64);
    const res = try RESP3Parser.parseAlloc(FloatDict, allocator, &MakeFloatMap().stream);
    testing.expect(12.34 == res.getValue("aaa").?);
    testing.expect(56.78 == res.getValue("bbb").?);
    testing.expect(99.99 == res.getValue("ccc").?);
}
fn MakeFloatMap() std.io.SliceInStream {
    return std.io.SliceInStream.init("%3\r\n$3\r\naaa\r\n,12.34\r\n$3\r\nbbb\r\n,56.78\r\n$3\r\nccc\r\n,99.99\r\n"[0..]);
}
fn MakeMap() std.io.SliceInStream {
    return std.io.SliceInStream.init("%3\r\n$5\r\nfirst\r\n,12.34\r\n$6\r\nsecond\r\n#t\r\n$5\r\nthird\r\n$11\r\nHello World\r\n"[0..]);
}
