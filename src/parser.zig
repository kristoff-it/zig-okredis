const std = @import("std");
const Reader = std.Io.Reader;
const fmt = std.fmt;
const testing = std.testing;
const InStream = std.io.InStream;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const BigNumParser = @import("./parser/t_bignum.zig").BigNumParser;
const BoolParser = @import("./parser/t_bool.zig").BoolParser;
const DoubleParser = @import("./parser/t_double.zig").DoubleParser;
const ListParser = @import("./parser/t_list.zig").ListParser;
const MapParser = @import("./parser/t_map.zig").MapParser;
const NumberParser = @import("./parser/t_number.zig").NumberParser;
const SetParser = @import("./parser/t_set.zig").SetParser;
const BlobStringParser = @import("./parser/t_string_blob.zig").BlobStringParser;
const SimpleStringParser = @import("./parser/t_string_simple.zig").SimpleStringParser;
const VoidParser = @import("./parser/void.zig").VoidParser;
const traits = @import("./traits.zig");

pub const RESP3Parser = struct {
    const rootParser = @This();

    pub fn parse(comptime T: type, r: *Reader) !T {
        const tag = try r.takeByte();
        return parseImpl(T, tag, .{}, r);
    }

    pub fn parseFromTag(comptime T: type, tag: u8, r: *Reader) !T {
        return parseImpl(T, tag, .{}, r);
    }

    pub fn parseAlloc(comptime T: type, allocator: Allocator, r: *Reader) !T {
        const tag = try r.takeByte();
        return try parseImpl(T, tag, .{ .ptr = allocator }, r);
    }

    pub fn parseAllocFromTag(
        comptime T: type,
        tag: u8,
        allocator: Allocator,
        r: *Reader,
    ) !T {
        return parseImpl(T, tag, .{ .ptr = allocator }, r);
    }

    // TODO: should the errorset really be anyerror? Should it be explicit?
    // const errorset = error{
    //     GotErrorReply,
    //     GotNilReply,
    //     LengthMismatch,
    //     UnsupportedConversion,

    //     SystemResources,
    //     InvalidCharacter,
    //     Overflow,
    //     InputOutput,
    //     IsDir,
    //     OperationAborted,
    //     BrokenPipe,
    //     ConnectionResetByPeer,
    //     WouldBlock,
    //     Unexpected,
    //     EndOfStream,
    //     OutOfMemory,
    //     GraveProtocolError,
    //     SorryBadImplementation,
    //     InvalidCharForDigit,
    //     DigitTooLargeForBase,
    //     InvalidBase,
    //     StreamTooLong,
    //     DecodeError,
    //     DecodingError,
    //     DivisionByZero,
    //     UnexpectedRemainder,
    // };

    // fn computeErrorSet(comptime T: type) type {
    //     if (comptime traits.isParserType(T)) {
    //         @compileLog("TYPE", @typeName(T), T.Redis.Parser.Errors);
    //         return errorset || T.Redis.Parser.Errors;
    //     }
    //     return errorset;
    // }
    pub fn parseImpl(
        comptime T: type,
        tag: u8,
        allocator: anytype,
        r: *Reader,
    ) anyerror!T {
        // First we get out of the way the basic case where
        // the return type is void and we just discard one full answer.
        if (T == void) return VoidParser.discardOne(tag, r);

        // Here we need to deal with optionals and pointers.
        // - Optionals imply the possibility of decoding a nil reply.
        // - Single-item pointers require us to allocate the type and recur.
        // - Slices are the only type of pointer that we want to delegate to sub-parsers.
        switch (@typeInfo(T)) {
            .optional => |opt| {
                var nextTag = tag;
                if (tag == '|') {
                    // If the type is an optional, we discard any potential attribute.
                    try VoidParser.discardOne('%', r);
                    nextTag = try r.takeByte();
                }

                // If we found nil, return immediately.
                if (nextTag == '_') {
                    try r.discardAll(2);
                    return null;
                }

                // Otherwise recur with the underlying type.
                return try parseImpl(opt.child, nextTag, allocator, r);
            },
            .pointer => |ptr| {
                if (!@hasField(@TypeOf(allocator), "ptr")) {
                    @compileError("`parse` can't perform allocations so it can't handle pointers, use `parseAlloc` instead.");
                }
                switch (ptr.size) {
                    .one => {
                        // Single-item pointer, allocate it and recur.
                        const res: *ptr.child = try allocator.ptr.create(ptr.child);
                        errdefer allocator.ptr.destroy(res);
                        res.* = try parseImpl(ptr.child, tag, allocator, r);
                        return res;
                    },
                    .many, .c => {
                        @panic("!");
                        // @compileError("Pointers to unknown size or C-type are not supported.");
                    },
                    .slice => {
                        // Slices are ok. We continue.
                    },
                }
            },
            else => {
                // Main case: no optionals, no single-item/unknown-size pointers.
                // We continue.
            },
        }

        var nextTag = tag;
        if (tag == '|') {
            // If the type declares to be able to decode attributes, we delegate immediately.
            if (comptime traits.handlesAttributes(T)) {
                const x: T = if (@hasField(@TypeOf(allocator), "ptr"))
                    try T.Redis.Parser.parseAlloc(tag, rootParser, allocator.ptr, r)
                else
                    try T.Redis.Parser.parse(tag, rootParser, r);
                return x;
            }
            // If we reached here, the type doesn't handle attributes so we must discard them.

            // Here we lie to the void parser and claim we want to discard one Map element.
            // We lie because attributes are not counted when consuming a reply with the
            // void parser. If we were to be truthful about the element type, the void
            // parser would also discard the actual reply.
            try VoidParser.discardOne('%', r);
            nextTag = try r.takeByte();
        }

        // If the type implement its own decoding procedure, we delegate the job to it.
        if (comptime traits.isParserType(T)) {
            const x: T = if (@hasField(@TypeOf(allocator), "ptr"))
                try T.Redis.Parser.parseAlloc(tag, rootParser, allocator.ptr, r)
            else
                try T.Redis.Parser.parse(nextTag, rootParser, r);
            return x;
        }

        switch (nextTag) {
            else => std.debug.panic("Found `{c}` in the main parser's switch." ++
                " Probably a bug in a type that implements `Redis.Parser`.", .{nextTag}),
            '_' => {
                try r.discardAll(2);
                return error.GotNilReply;
            },
            '-' => {
                try VoidParser.discardOne('+', r);
                return error.GotErrorReply;
            },
            '!' => {
                try VoidParser.discardOne('$', r);
                return error.GotErrorReply;
            },
            ':' => return try ifSupported(NumberParser, T, allocator, r),
            ',' => return try ifSupported(DoubleParser, T, allocator, r),
            '#' => return try ifSupported(BoolParser, T, allocator, r),
            '$', '=' => return try ifSupported(BlobStringParser, T, allocator, r),
            '+' => return try ifSupported(SimpleStringParser, T, allocator, r),
            '*' => return try ifSupported(ListParser, T, allocator, r),
            '~' => return try ifSupported(SetParser, T, allocator, r),
            '%' => return try ifSupported(MapParser, T, allocator, r),
            '(' => return try ifSupported(BigNumParser, T, allocator, r),
        }
    }

    fn ifSupported(
        comptime parser: type,
        comptime T: type,
        allocator: anytype,
        r: *Reader,
    ) !T {
        if (@hasField(@TypeOf(allocator), "ptr")) {
            return if (comptime parser.isSupportedAlloc(T))
                parser.parseAlloc(T, rootParser, allocator.ptr, r)
            else
                error.UnsupportedConversion;
        } else {
            return if (comptime parser.isSupported(T))
                parser.parse(T, rootParser, r)
            else
                error.UnsupportedConversion;
        }
    }

    // Frees values created by `sendAlloc`.
    // If the top value is a pointer, it frees that too.
    // TODO: free stdlib types!
    pub fn freeReply(val: anytype, allocator: Allocator) void {
        const T = @TypeOf(val);

        switch (@typeInfo(T)) {
            else => return,
            .optional => if (val) |v| freeReply(v, allocator),
            .array => |arr| {
                switch (@typeInfo(arr.child)) {
                    else => {},
                    .@"enum",
                    .@"union",
                    .@"struct",
                    .pointer,
                    .optional,
                    => {
                        for (val) |elem| {
                            freeReply(elem, allocator);
                        }
                    },
                }
                // allocator.free(val);
            },
            .pointer => |ptr| switch (ptr.size) {
                .many => @compileError("sendAlloc is incapable of generating [*] pointers. " ++
                    "You are passing the wrong value!"),
                .c => allocator.free(val),
                .slice => {
                    switch (@typeInfo(ptr.child)) {
                        else => {},
                        .@"enum",
                        .@"union",
                        .@"struct",
                        .pointer,
                        .optional,
                        => {
                            for (val) |elem| {
                                freeReply(elem, allocator);
                            }
                        },
                    }
                    allocator.free(val);
                },
                .one => {
                    switch (@typeInfo(ptr.child)) {
                        else => {},
                        .@"enum",
                        .@"union",
                        .@"struct",
                        .pointer,
                        .optional,
                        => {
                            freeReply(val.*, allocator);
                        },
                    }
                    allocator.destroy(val);
                },
            },
            .@"union" => if (comptime traits.isParserType(T)) {
                T.Redis.Parser.destroy(val, rootParser, allocator);
            } else {
                @compileError("sendAlloc cannot return Unions or Enums that don't implement " ++
                    "custom parsing logic. You are passing the wrong value!");
            },
            .@"struct" => |stc| {
                if (comptime traits.isParserType(T)) {
                    T.Redis.Parser.destroy(val, rootParser, allocator);
                } else {
                    inline for (stc.fields) |f| {
                        switch (@typeInfo(f.type)) {
                            else => {},
                            .@"enum",
                            .@"union",
                            .@"struct",
                            .pointer,
                            .optional,
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

test "parser" {
    _ = @import("./parser/t_bignum.zig");
    _ = @import("./parser/t_number.zig");
    _ = @import("./parser/t_bool.zig");
    _ = @import("./parser/t_string_blob.zig");
    _ = @import("./parser/t_string_simple.zig");
    _ = @import("./parser/t_double.zig");
    _ = @import("./parser/t_list.zig");
    _ = @import("./parser/t_set.zig");
    _ = @import("./parser/t_map.zig");
    _ = @import("./parser/void.zig");
}

test "evil indirection" {
    const allocator = std.heap.page_allocator;

    {
        var r_evil_f = MakeEvilFloat();
        const yes = try RESP3Parser.parseAlloc(?**?*f32, allocator, &r_evil_f);
        defer RESP3Parser.freeReply(yes, allocator);

        if (yes) |v| {
            try testing.expectEqual(@as(f32, 123.45), v.*.*.?.*);
        } else {
            unreachable;
        }
    }

    {
        var r_evil_nil = MakeEvilNil();
        const no = try RESP3Parser.parseAlloc(?***f32, allocator, &r_evil_nil);
        if (no) |_| unreachable;
    }

    {
        // const WithAttribs = @import("./types/attributes.zig").WithAttribs;
        // const OrErr = @import("./types/error.zig").OrErr;
        // const yes = try RESP3Parser.parseAlloc(***WithAttribs(?***f32), allocator, &MakeEvilFloat().stream);
        // defer RESP3Parser.freeReply(yes, allocator);
        // std.debug.warn("{?}\n", yes.*.*.*.attribs);

        // if (yes.*.*.data) |v| {
        //     //try testing.expectEqual(f32(123.45), v.*.*.*);
        // } else {
        //     unreachable;
        // }
    }
}

// zig fmt: off
fn MakeEvilFloat() Reader {
    return std.Io.Reader.fixed(
        ("|2\r\n" ++
            "+Ciao\r\n" ++
            "+World\r\n" ++
            "+Peach\r\n" ++
            ",9.99\r\n" ++
        ",123.45\r\n")
    [0..]);
}

fn MakeEvilNil() Reader {
    return std.Io.Reader.fixed(
        ("|2\r\n" ++
            "+Ciao\r\n" ++
            "+World\r\n" ++
            "+Peach\r\n" ++
            ",9.99\r\n" ++
        "_\r\n")
    [0..]);
}
// zig fmt: on

test "float" {

    // No alloc
    {
        var r_float = std.Io.Reader.fixed(",120.23\r\n"[0..]);
        const p1 = RESP3Parser.parse(f32, &r_float) catch unreachable;
        try testing.expect(p1 == 120.23);
    }

    //Alloc
    const allocator = std.heap.page_allocator;
    {
        {
            var r_1f = Make1Float();
            const f = try RESP3Parser.parseAlloc(*f32, allocator, &r_1f);
            defer allocator.destroy(f);
            try testing.expect(f.* == 120.23);
        }
        {
            var r_2f = Make2Float();
            const f = try RESP3Parser.parseAlloc([]f32, allocator, &r_2f);
            defer allocator.free(f);
            try testing.expectEqualSlices(f32, &[_]f32{ 1.1, 2.2 }, f);
        }
    }
}

fn Make1Float() Reader {
    return std.Io.Reader.fixed(",120.23\r\n"[0..]);
}

fn Make2Float() Reader {
    return std.Io.Reader.fixed("*2\r\n,1.1\r\n,2.2\r\n"[0..]);
}

test "optional" {
    const maybeInt: ?i64 = null;
    const maybeBool: ?bool = null;
    const maybeArr: ?[4]bool = null;
    var r_null = MakeNull();
    try testing.expectEqual(maybeInt, try RESP3Parser.parse(?i64, &r_null));
    r_null.seek = 0;
    try testing.expectEqual(maybeBool, try RESP3Parser.parse(?bool, &r_null));
    r_null.seek = 0;
    try testing.expectEqual(maybeArr, try RESP3Parser.parse(?[4]bool, &r_null));
}
fn MakeNull() Reader {
    return std.Io.Reader.fixed("_\r\n"[0..]);
}

test "array" {
    var r_arr = MakeArray();
    try testing.expectError(error.LengthMismatch, RESP3Parser.parse([5]i64, &r_arr));
    //try testing.expectError(error.LengthMismatch, RESP3Parser.parse([0]i64, MakeArray().reader()));
    r_arr.seek = 0;
    try testing.expectError(error.UnsupportedConversion, RESP3Parser.parse([2]i64, &r_arr));
    r_arr.seek = 0;
    try testing.expectEqual([2]f32{ 1.2, 3.4 }, try RESP3Parser.parse([2]f32, &r_arr));
}
fn MakeArray() Reader {
    return std.Io.Reader.fixed("*2\r\n,1.2\r\n,3.4\r\n"[0..]);
}

test "string" {
    var r_str = MakeString();
    try testing.expectError(error.LengthMismatch, RESP3Parser.parse(
        [5]u8,
        &r_str,
    ));
    r_str.seek = 0;
    try testing.expectError(
        error.LengthMismatch,
        RESP3Parser.parse([2]u16, &r_str),
    );
    var r_str2 = MakeSimpleString();
    try testing.expectEqualSlices(u8, "Hello World!", &try RESP3Parser.parse(
        [12]u8,
        &r_str2,
    ));
    r_str2.seek = 0;
    try testing.expectError(
        error.LengthMismatch,
        RESP3Parser.parse([13]u8, &r_str2),
    );

    const allocator = std.heap.page_allocator;
    r_str.seek = 0;
    try testing.expectEqualSlices(u8, "Banana", try RESP3Parser.parseAlloc(
        []u8,
        allocator,
        &r_str,
    ));
    r_str2.seek = 0;
    try testing.expectEqualSlices(u8, "Hello World!", try RESP3Parser.parseAlloc(
        []u8,
        allocator,
        &r_str2,
    ));
}
fn MakeString() Reader {
    return std.Io.Reader.fixed("$6\r\nBanana\r\n"[0..]);
}
fn MakeSimpleString() Reader {
    return std.Io.Reader.fixed("+Hello World!\r\n"[0..]);
}

test "map2struct" {
    const FixBuf = @import("./types/fixbuf.zig").FixBuf;
    const MyStruct = struct {
        first: f32,
        second: bool,
        third: FixBuf(11),
    };
    var r_map = MakeMap();
    const res = try RESP3Parser.parse(MyStruct, &r_map);
    try testing.expect(res.first == 12.34);
    try testing.expect(res.second == true);
    try testing.expectEqualSlices(u8, "Hello World", res.third.toSlice());
}
test "hashmap" {
    const allocator = std.heap.page_allocator;
    const FloatDict = std.StringHashMap(f64);
    var r_map = MakeFloatMap();
    const res = try RESP3Parser.parseAlloc(FloatDict, allocator, &r_map);
    try testing.expect(12.34 == res.get("aaa").?);
    try testing.expect(56.78 == res.get("bbb").?);
    try testing.expect(99.99 == res.get("ccc").?);
}
// TODO: get rid if this
fn MakeFloatMap() Reader {
    return std.Io.Reader.fixed("%3\r\n$3\r\naaa\r\n,12.34\r\n$3\r\nbbb\r\n,56.78\r\n$3\r\nccc\r\n,99.99\r\n"[0..]);
}
fn MakeMap() Reader {
    return std.Io.Reader.fixed("%3\r\n$5\r\nfirst\r\n,12.34\r\n$6\r\nsecond\r\n#t\r\n$5\r\nthird\r\n$11\r\nHello World\r\n"[0..]);
}

test "consume right amount" {
    const FixBuf = @import("./types/fixbuf.zig").FixBuf;

    {
        var r_err = std.Io.Reader.fixed("-ERR banana\r\n"[0..]);
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(void, &r_err));
        try testing.expectError(error.EndOfStream, r_err.takeByte());

        r_err.seek = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(i64, &r_err));
        try testing.expectError(error.EndOfStream, r_err.takeByte());

        r_err.seek = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(FixBuf(100), &r_err));
        try testing.expectError(error.EndOfStream, r_err.takeByte());
    }

    {
        var r_err = std.Io.Reader.fixed("!10\r\nERR banana\r\n"[0..]);
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(void, &r_err));
        try testing.expectError(error.EndOfStream, r_err.takeByte());

        r_err.seek = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(u64, &r_err));
        try testing.expectError(error.EndOfStream, r_err.takeByte());

        r_err.seek = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse([10]u8, &r_err));
        try testing.expectError(error.EndOfStream, r_err.takeByte());
    }

    {
        var r_err = std.Io.Reader.fixed("*2\r\n:123\r\n!10\r\nERR banana\r\n"[0..]);
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse([2]u64, &r_err));
        try testing.expectError(error.EndOfStream, r_err.takeByte());

        const MyStruct = struct {
            a: u8,
            b: u8,
        };
        r_err.seek = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(MyStruct, &r_err));
        try testing.expectError(error.EndOfStream, r_err.takeByte());
    }

    {
        var r_err = std.Io.Reader.fixed("*2\r\n:123\r\n!10\r\nERR banana\r\n"[0..]);
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse([2]u64, &r_err));
        try testing.expectError(error.EndOfStream, r_err.takeByte());

        const MyStruct = struct {
            a: u8,
            b: u8,
        };
        r_err.seek = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(MyStruct, &r_err));
        try testing.expectError(error.EndOfStream, r_err.takeByte());
    }
}
