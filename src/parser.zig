const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;
const InStream = std.io.InStream;
const Allocator = std.mem.Allocator;

const VoidParser = @import("./parser/void.zig").VoidParser;
const NumberParser = @import("./parser/t_number.zig").NumberParser;
const BoolParser = @import("./parser/t_bool.zig").BoolParser;
const BlobStringParser = @import("./parser/t_string_blob.zig").BlobStringParser;
const SimpleStringParser = @import("./parser/t_string_simple.zig").SimpleStringParser;
const DoubleParser = @import("./parser/t_double.zig").DoubleParser;
const ListParser = @import("./parser/t_list.zig").ListParser;
const MapParser = @import("./parser/t_map.zig").MapParser;
const traits = @import("./traits.zig");

/// This is the RESP3 parser. It reads an OutStream and returns redis replies.
/// The user is required to specify how they want to decode each reply.
///
/// The parser supports all 1:1 translations (e.g. RESPNumber -> Int) and
/// a couple quality-of-life custom ones:
///     - RedisStrings can be parsed to numbers (the parser will use fmt.parse{Int,Float})
///     - RedisHashes can be parsed into HashMaps and Structs
///
/// Additionally, the parser can be extented. If the type requested declares
/// a `Redis.Parser` member, then their .parse/.parseAlloc will be called.
///
/// There are two included types that implement the `Redis` trait
///     - OrErr(T) is a union over a user type that parses Redis errors
///     - FixBuf(N) is a fixed-length buffer used to decode strings
///       without dynamic allocations.
///
/// Redis Errors are treated as special values, so there is no way
/// to parse them other than wrapping the expected result type with OrErr().
/// Asking for an incompatible return type will return a Zig error and
/// will leave the connection in a corrupted state.
/// (this constraint might be relaxed in the future)
///
/// If the return value of a command is not needed, it's also possible to
/// use the `void` type. This will succesfully decode any type of response
/// to a command _except_ for RedisErrors. Use OrErr(void) to ensure a command
/// decode step never fails.
pub const RESP3Parser = struct {
    const rootParser = @This();

    /// This is the parsing interface that doesn't requre an allocator.
    /// As such it doesn't support pointers, but it can still use objects
    /// That implement the `Redis` trait. The easiest way to decode strings
    /// using this function is to use a FixBuf wherever a string is expected.
    pub inline fn parse(comptime T: type, msg: var) !T {
        const tag = try msg.readByte();
        return parseFromTag(T, tag, msg);
    }

    /// Used by the sub-parsers and `Redis` types to delegate parsing to another
    /// parser. It's used for example by OrErr to continue parsing in the event
    /// that the reply is not a Redis error.
    pub fn parseFromTag(comptime T: type, tag: u8, msg: var) !T {
        if (T == void) return VoidParser.parseVoid(tag, msg);

        comptime var RealType = T;
        switch (@typeInfo(T)) {
            .Pointer => @compileError("`parse` can't perform allocations so it can't handle pointers, use `parseAlloc` instead."),
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

        // Here we check for the `Redis.Parser` trait, in order to delegate the parsing job.
        if (comptime traits.isParserType(RealType)) {
            return RealType.Redis.Parser.parse(tag, rootParser, msg);
        }

        // Call the right parser based on the tag we just read from the stream.
        return switch (tag) {
            ':' => try ifSupported(NumberParser, RealType, msg),
            ',' => try ifSupported(DoubleParser, RealType, msg),
            '#' => try ifSupported(BoolParser, RealType, msg),
            '$' => try ifSupported(BlobStringParser, RealType, msg),
            '+' => try ifSupported(SimpleStringParser, RealType, msg),
            '-', '!' => return error.GotErrorReply,
            '*' => try ifSupported(ListParser, RealType, msg),
            '%' => try ifSupported(MapParser, RealType, msg),
            // '_' => error.UnexpectedNilReply, // TODO: consider supporting it only for CRedisReply types!
            else => return error.ProtocolError,
        };
    }
    // TODO: if no parser supports the type conversion, @compileError!
    // The whole job of this function is to cut away calls to sub-parsers
    // if we know that the Zig type is not supported.
    // It's a good way to report a comptime error if no parser supports a
    // given type.
    inline fn ifSupported(comptime parser: type, comptime T: type, msg: var) !T {
        return if (comptime parser.isSupported(T))
            parser.parse(T, rootParser, msg)
        else
            return error.UnsupportedConversion;
    }

    /// This is the interface that accepts an allocator.
    pub fn parseAlloc(comptime T: type, allocator: *Allocator, msg: var) !T {
        const tag = try msg.readByte();
        return parseAllocFromTag(T, tag, allocator, msg);
    }

    pub fn parseAllocFromTag(comptime T: type, tag: u8, allocator: *Allocator, msg: var) !T {
        if (T == void) return VoidParser.parseVoid(tag, msg);

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

        if (comptime traits.isParserType(RealType))
            return RealType.Redis.Parser.parseAlloc(tag, rootParser, allocator, msg);

        return switch (tag) {
            ':' => try ifSupportedAlloc(NumberParser, RealType, allocator, msg),
            ',' => try ifSupportedAlloc(DoubleParser, RealType, allocator, msg),
            '#' => try ifSupportedAlloc(BoolParser, RealType, allocator, msg),
            '$' => try ifSupportedAlloc(BlobStringParser, RealType, allocator, msg),
            '+' => try ifSupportedAlloc(SimpleStringParser, RealType, allocator, msg),
            '-', '!' => return error.UnexpectedErrorReply,
            '*' => try ifSupportedAlloc(ListParser, RealType, allocator, msg),
            '%' => try ifSupportedAlloc(MapParser, RealType, allocator, msg),
            // '_' => error.NilButNoOptional, // TODO: consider supporting it only for CRedisReply types!
            else => @panic("Encountered grave protocol error"),
        };
    }

    inline fn ifSupportedAlloc(comptime parser: type, comptime T: type, allocator: *Allocator, msg: var) !T {
        return if (comptime parser.isSupportedAlloc(T))
            parser.parseAlloc(T, rootParser, allocator, msg)
        else
            error.UnsupportedConversion;
    }

    // Frees values created by `sendAlloc`.
    // If the top value is a pointer, it frees that too.
    pub fn freeReply(val: var, allocator: *Allocator) void {
        const T = @typeOf(val);
        switch (@typeInfo(T)) {
            else => return,
            .Optional => if (val) |v| freeReply(val),
            .Array => |arr| {
                switch (arr.child) {
                    else => {},
                    .Enum,
                    .Union,
                    .Struct,
                    .Pointer,
                    .Optional,
                    => {
                        for (val) |elem| {
                            freeReply(elem, allocator);
                        }
                    },
                }
                allocator.free(val);
            },
            .Pointer => |ptr| switch (ptr.size) {
                .Many => @compileError("sendAlloc is incapable of generating [*] pointers. " ++
                    "You are passing the wrong value!"),
                .C => allocator.free(val),
                .Slice => {
                    switch (@typeInfo(ptr.child)) {
                        else => {},
                        .Enum,
                        .Union,
                        .Struct,
                        .Pointer,
                        .Optional,
                        => {
                            for (val) |elem| {
                                freeReply(elem, allocator);
                            }
                        },
                    }
                    allocator.free(val);
                },
                .One => {
                    switch (@typeInfo(ptr.child)) {
                        else => {},
                        .Enum,
                        .Union,
                        .Struct,
                        .Pointer,
                        .Optional,
                        => {
                            freeReply(val.*, allocator);
                        },
                    }
                    allocator.destroy(val);
                },
            },
            .Union => |unn| if (comptime traits.isParserType(T)) {
                T.Redis.Parser.destroy(val, rootParser, allocator);
            } else {
                @compileError("sendAlloc cannot return Unions or Enums that don't implement " ++
                    "custom parsing logic. You are passing the wrong value!");
            },
            .Struct => |stc| {
                if (comptime traits.isParserType(T)) {
                    T.Redis.Parser.destroy(val, rootParser, allocator);
                } else {
                    inline for (stc.fields) |f| {
                        switch (@typeInfo(f.field_type)) {
                            else => {},
                            .Enum,
                            .Union,
                            .Struct,
                            .Pointer,
                            .Optional,
                            => {
                                freeReply(@field(val, f.name), allocator);
                            },
                        }
                    }
                }
            },
        }
    }
};

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

test "parser" {
    _ = @import("./parser/void.zig");
    _ = @import("./parser/t_number.zig");
    _ = @import("./parser/t_bool.zig");
    _ = @import("./parser/t_string_blob.zig");
    _ = @import("./parser/t_string_simple.zig");
    _ = @import("./parser/t_double.zig");
    _ = @import("./parser/t_list.zig");
    _ = @import("./parser/t_map.zig");
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
    const FixBuf = @import("./types/fixbuf.zig").FixBuf;
    const MyStruct = struct {
        first: f32,
        second: bool,
        third: FixBuf(11),
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
