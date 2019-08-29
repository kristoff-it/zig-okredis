const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;
const InStream = std.io.InStream;
const Allocator = std.mem.Allocator;

const BigNumParser = @import("./parser/t_bignum.zig").BigNumParser;
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
/// The parser supports all 1:1 translations (e.g. RESP Number -> Int) and
/// a couple quality-of-life custom ones:
///     - RESP Strings can be parsed to numbers (the parser will use fmt.parse{Int,Float})
///     - RESP Maps can be parsed into std.HashMaps and Structs
///
/// Additionally, the parser can be extented. If the type requested declares
/// a `Redis.Parser` member, then their .parse/.parseAlloc will be called.
///
/// There are two included types that implement the `Redis.Parser` trait
///     - OrErr(T) is a union over a user type that parses Redis errors
///     - FixBuf(N) is a fixed-length buffer used to decode strings
///       without dynamic allocations.
///
/// Redis Errors are treated as special values, so they won't decode to
/// strings ([]u8) or other generic types. Same with `void`: it will discard
/// any reply *EXCEPT* for Redis errors. When the reply contains an error, the
/// Zig `error.GorErrorReply` error will be returned. This makes it impossible
/// to erroneusly ignore error replies, but discards the error message that
/// Redis sent. To decode a Redis error reply as a value, in order to inspect
/// the error code for example, one must wrap the expected type with OrErr or a
/// similar type. Asking for an incompatible type will return a Zig error and
/// will leave the connection in a corrupted state.
///
/// If the return value of a command is not needed, it's also possible to use
/// the `void` type. This will succesfully decode any type of response to a
/// command _except_ for RedisErrors. Use OrErr(void) to ensure a command
/// decode step never fails.
pub const RESP3Parser = struct {
    const rootParser = @This();

    /// This is the parsing interface that doesn't requre an allocator.
    /// As such it doesn't support pointers, but it can still use types
    /// that implement the `Redis.Parser` trait. The easiest way to decode strings
    /// using this function is to use a FixBuf wherever a string is expected.
    pub inline fn parse(comptime T: type, msg: var) !T {
        const tag = try msg.readByte();
        return parseFromTag(T, tag, msg);
    }

    /// Used by the sub-parsers and `Redis.Parser` types to delegate parsing to another
    /// parser. It's used for example by OrErr to continue parsing in the event
    /// that the reply is not a Redis error (i.e. the tag is not '!' nor '-').
    pub fn parseFromTag(comptime T: type, tag: u8, msg: var) !T {
        if (T == void) return VoidParser.discardOne(tag, msg);

        comptime var UnwrappedType = T;
        switch (@typeInfo(T)) {
            .Pointer => @compileError("`parse` can't perform allocations so it can't handle pointers, use `parseAlloc` instead."),
            .Optional => |opt| UnwrappedType = opt.child,
            else => {},
        }

        // At this point there might be an attribute in the stream. We default
        // to discarding attributes, but some types might want access to them,
        // like WithAttribs() for example. If there is an attribute and the type
        // doesn't want it, we discard it and try consuming again a nil reply
        // if the type is an optional.
        if (tag == '|') {
            if (comptime traits.handlesAttributes(UnwrappedType)) {
                return UnwrappedType.Redis.Parser.parse(tag, rootParser, msg);
            }

            // Here we lie to the void parser and claim we want to discard one Map element.
            try VoidParser.discardOne('%', msg);
        }

        // Try to decode a null if T was an optional.
        if (@typeId(T) == .Optional) {
            // Null micro-parser:
            if (tag == '_') {
                try msg.skipBytes(2);
                return null;
            }
        }

        // Here we check for the `Redis.Parser` trait, in order to delegate the parsing job.
        if (comptime traits.isParserType(UnwrappedType)) {
            return UnwrappedType.Redis.Parser.parse(tag, rootParser, msg);
        }

        // Call the right parser based on the tag we just read from the stream.
        return switch (tag) {
            else => std.debug.panic("Found `{}` in the main parser's switch." ++
                " Probably a bug in a type that implements `Redis.Parser`.", tag),
            '_' => return error.GotNilReply,
            '-', '!' => return error.GotErrorReply,
            ':' => try ifSupported(NumberParser, UnwrappedType, msg),
            ',' => try ifSupported(DoubleParser, UnwrappedType, msg),
            '#' => try ifSupported(BoolParser, UnwrappedType, msg),
            '$', '=' => try ifSupported(BlobStringParser, UnwrappedType, msg),
            '+' => try ifSupported(SimpleStringParser, UnwrappedType, msg),
            '*' => try ifSupported(ListParser, UnwrappedType, msg),
            '%' => try ifSupported(MapParser, UnwrappedType, msg),
            // The bignum parser needs an allocator so it will refuse
            // all types when calling .isSupported() on it.
            '(' => try ifSupported(BigNumParser, UnwrappedType, msg),
        };
    }

    // TODO: if no parser supports the type conversion, @compileError!
    // The whole job of this function is to cut away calls to sub-parsers if we
    // know that the Zig type is not supported.  It's a good way to report a
    // comptime error if no parser supports a given type.
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
        if (T == void) return VoidParser.discardOne(tag, msg);

        comptime var UnwrappedType = T;
        switch (@typeInfo(T)) {
            .Optional => |opt| UnwrappedType = opt.child,
            else => {},
        }

        // We now are in one of three main situations:
        // - The type is not a pointer.
        // - The type is a pointer to many items (slice).
        // - The type is a pointer to a single item.
        //
        // The first case is trivial, we just pass it around and all works just
        // like with `parse`, with the only difference being that we are
        // passing around an allocator, to let all sub-parsers allocate memory
        // as they see fit.
        //
        // The second case is slightly more complex: A slice might mean a
        // string or a sequence of more complex elements ([]u8 vs []u32 vs
        // []KV([]u8, f32)).  The main parser doesn't really care which case it
        // is because the actual resolution will be handled by `t_list`,
        // `t_set`, `t_map`, or `t_string_*`.
        //
        // The last case is similar to the first, but since the type is a
        // pointer, we must allocate it dynamically. In this case we hide to
        // sub-parsers the fact that the type requested is a pointer and not a
        // "concrete" type, by just writing the result of their invocation into
        // dyn memory allocated by us. It was a bit confusing in the beginning
        // to decide what should sub-parsers know or not, but this seems a good
        // balance. There are small implications with how certain types get
        // interpreted, but it's mostly corner-cases with little pratical
        // utility, and each has an escape hatch. An example of ambiguity is
        // that asking for a *u8 will be interpreted as a request for a
        // dynamically allocated numeric value and not for a single-chararacter
        // string. This is better discussed inside the string-related
        // sub-parsers.
        comptime var InnerType = UnwrappedType;
        switch (@typeInfo(UnwrappedType)) {
            .Pointer => |ptr| switch (ptr.size) {
                .Many => @compileError("Pointers to unknown size of elements " ++
                    "are not supported, use a slice or, for C-compatible strings, a c-pointer."),
                // We only "hide" the pointer indirection
                // only for pointers to single items.
                .One => InnerType = ptr.child,
                else => {},
            },
            else => {},
        }

        // Same as with `parseFromTag`, we might have an attribute in the
        // stream. We need to decide wether to discard it or let the underlying
        // type decode it. Recursion is necessary to let the nil parser try
        // again to decode a nil value, as it would have been obscured by the
        // interleaved attribute. Read the corresponding comment in
        // `parseFromTag` for more information.
        if (tag == '|') {
            if (comptime traits.handlesAttributes(InnerType)) {
                // If the type is a single-item ptr, allocate.  If it's a
                // pointer to a slice, the check to `handlesAttributes` would
                // have failed because it would see the pointer type and not
                // the underlying child type, so the else branch must happen
                // only with non-pointer types, requiring no allocation from
                // us.
                if (InnerType != UnwrappedType) {
                    var res = try allocator.create(InnerType);
                    errdefer allocator.destroy(res);
                    res.* = try InnerType.Redis.Parser.parseAlloc(tag, rootParser, allocator, msg);
                    return res;
                }

                return InnerType.Redis.Parser.parseAlloc(tag, rootParser, allocator, msg);
            }

            // Here we lie to the void parser and claim we want to discard one Map element.
            try VoidParser.discardOne('%', msg);
        }

        // Try to decode a null if T was an optional.
        if (@typeId(T) == .Optional) {
            // Null micro-parser:
            if (tag == '_') {
                try msg.skipBytes(2);
                return null;
            }
        }

        if (comptime traits.isParserType(InnerType)) {
            // Same as a few lines before, we allocate in case of a single item
            // pointer. Read the previus comment for more information.
            if (InnerType != UnwrappedType) {
                var res: UnwrappedType = try allocator.create(InnerType);
                errdefer allocator.destroy(res);
                res.* = try InnerType.Redis.Parser.parseAlloc(tag, rootParser, allocator, msg);
                return res;
            }

            return InnerType.Redis.Parser.parseAlloc(tag, rootParser, allocator, msg);
        }

        if (InnerType != UnwrappedType) {
            var res = try allocator.create(InnerType);
            errdefer allocator.destroy(res);
            res.* = try doParseAlloc(tag, InnerType, allocator, msg);
            return res;
        }

        return doParseAlloc(tag, UnwrappedType, allocator, msg);
    }

    // The last step of parseAllocFromTag is in a separate function to reduce
    // the amount of duplicated code caused by the fact that for single item
    // pointers we are allocating the memory here, in the root parser. This
    // causes code duplication because of branching.
    inline fn doParseAlloc(tag: u8, comptime T: type, allocator: *Allocator, msg: var) !T {
        return switch (tag) {
            else => std.debug.panic("Found `{c}` in the main parser's switch." ++
                " Probably a bug in a type that implements `Redis.Parser`.", tag),
            '_' => return error.GotNilReply,
            '-', '!' => return error.GotErrorReply,
            ':' => try ifSupportedAlloc(NumberParser, T, allocator, msg),
            ',' => try ifSupportedAlloc(DoubleParser, T, allocator, msg),
            '#' => try ifSupportedAlloc(BoolParser, T, allocator, msg),
            '$', '=' => try ifSupportedAlloc(BlobStringParser, T, allocator, msg),
            '+' => try ifSupportedAlloc(SimpleStringParser, T, allocator, msg),
            '*' => try ifSupportedAlloc(ListParser, T, allocator, msg),
            '%' => try ifSupportedAlloc(MapParser, T, allocator, msg),
            '(' => try ifSupportedAlloc(BigNumParser, T, allocator, msg),
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
    // TODO: free stdlib types!
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
    _ = @import("./parser/t_bignum.zig");
    _ = @import("./parser/t_number.zig");
    _ = @import("./parser/t_bool.zig");
    _ = @import("./parser/t_string_blob.zig");
    _ = @import("./parser/t_string_simple.zig");
    _ = @import("./parser/t_double.zig");
    _ = @import("./parser/t_list.zig");
    _ = @import("./parser/t_map.zig");
    _ = @import("./parser/void.zig");
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
