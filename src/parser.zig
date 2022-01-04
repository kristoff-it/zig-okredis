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
const SetParser = @import("./parser/t_set.zig").SetParser;
const MapParser = @import("./parser/t_map.zig").MapParser;
const traits = @import("./traits.zig");

pub const RESP3Parser = struct {
    const rootParser = @This();

    pub fn parse(comptime T: type, msg: anytype) !T {
        const tag = try msg.readByte();
        return parseImpl(T, tag, .{}, msg);
    }

    pub fn parseFromTag(comptime T: type, tag: u8, msg: anytype) !T {
        return parseImpl(T, tag, .{}, msg);
    }

    pub fn parseAlloc(comptime T: type, allocator: Allocator, msg: anytype) !T {
        const tag = try msg.readByte();
        return try parseImpl(T, tag, .{ .ptr = allocator }, msg);
    }

    pub fn parseAllocFromTag(comptime T: type, tag: u8, allocator: Allocator, msg: anytype) !T {
        return parseImpl(T, tag, .{ .ptr = allocator }, msg);
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
    pub fn parseImpl(comptime T: type, tag: u8, allocator: anytype, msg: anytype) anyerror!T {
        // First we get out of the way the basic case where
        // the return type is void and we just discard one full answer.
        if (T == void) return VoidParser.discardOne(tag, msg);

        // Here we need to deal with optionals and pointers.
        // - Optionals imply the possibility of decoding a nil reply.
        // - Single-item pointers require us to allocate the type and recur.
        // - Slices are the only type of pointer that we want to delegate to sub-parsers.
        switch (@typeInfo(T)) {
            .Optional => |opt| {
                var nextTag = tag;
                if (tag == '|') {
                    // If the type is an optional, we discard any potential attribute.
                    try VoidParser.discardOne('%', msg);
                    nextTag = try msg.readByte();
                }

                // If we found nil, return immediately.
                if (nextTag == '_') {
                    try msg.skipBytes(2, .{});
                    return null;
                }

                // Otherwise recur with the underlying type.
                return try parseImpl(opt.child, nextTag, allocator, msg);
            },
            .Pointer => |ptr| {
                if (!@hasField(@TypeOf(allocator), "ptr")) {
                    @compileError("`parse` can't perform allocations so it can't handle pointers, use `parseAlloc` instead.");
                }
                switch (ptr.size) {
                    .One => {
                        // Single-item pointer, allocate it and recur.
                        var res: *ptr.child = try allocator.ptr.create(ptr.child);
                        errdefer allocator.ptr.destroy(res);
                        res.* = try parseImpl(ptr.child, tag, allocator, msg);
                        return res;
                    },
                    .Many, .C => {
                        @panic("!");
                        // @compileError("Pointers to unknown size or C-type are not supported.");
                    },
                    .Slice => {
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
                var x: T = if (@hasField(@TypeOf(allocator), "ptr"))
                    try T.Redis.Parser.parseAlloc(tag, rootParser, allocator.ptr, msg)
                else
                    try T.Redis.Parser.parse(tag, rootParser, msg);
                return x;
            }
            // If we reached here, the type doesn't handle attributes so we must discard them.

            // Here we lie to the void parser and claim we want to discard one Map element.
            // We lie because attributes are not counted when consuming a reply with the
            // void parser. If we were to be truthful about the element type, the void
            // parser would also discard the actual reply.
            try VoidParser.discardOne('%', msg);
            nextTag = try msg.readByte();
        }

        // If the type implement its own decoding procedure, we delegate the job to it.
        if (comptime traits.isParserType(T)) {
            var x: T = if (@hasField(@TypeOf(allocator), "ptr"))
                try T.Redis.Parser.parseAlloc(tag, rootParser, allocator.ptr, msg)
            else
                try T.Redis.Parser.parse(nextTag, rootParser, msg);
            return x;
        }

        switch (nextTag) {
            else => std.debug.panic("Found `{c}` in the main parser's switch." ++
                " Probably a bug in a type that implements `Redis.Parser`.", .{nextTag}),
            '_' => {
                try msg.skipBytes(2, .{});
                return error.GotNilReply;
            },
            '-' => {
                try VoidParser.discardOne('+', msg);
                return error.GotErrorReply;
            },
            '!' => {
                try VoidParser.discardOne('$', msg);
                return error.GotErrorReply;
            },
            ':' => return try ifSupported(NumberParser, T, allocator, msg),
            ',' => return try ifSupported(DoubleParser, T, allocator, msg),
            '#' => return try ifSupported(BoolParser, T, allocator, msg),
            '$', '=' => return try ifSupported(BlobStringParser, T, allocator, msg),
            '+' => return try ifSupported(SimpleStringParser, T, allocator, msg),
            '*' => return try ifSupported(ListParser, T, allocator, msg),
            '~' => return try ifSupported(SetParser, T, allocator, msg),
            '%' => return try ifSupported(MapParser, T, allocator, msg),
            '(' => return try ifSupported(BigNumParser, T, allocator, msg),
        }
    }

    fn ifSupported(comptime parser: type, comptime T: type, allocator: anytype, msg: anytype) !T {
        if (@hasField(@TypeOf(allocator), "ptr")) {
            return if (comptime parser.isSupportedAlloc(T))
                parser.parseAlloc(T, rootParser, allocator.ptr, msg)
            else
                error.UnsupportedConversion;
        } else {
            return if (comptime parser.isSupported(T))
                parser.parse(T, rootParser, msg)
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
            .Optional => if (val) |v| freeReply(v, allocator),
            .Array => |arr| {
                switch (@typeInfo(arr.child)) {
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
                // allocator.free(val);
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
            .Union => if (comptime traits.isParserType(T)) {
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
        const yes = try RESP3Parser.parseAlloc(?**?*f32, allocator, MakeEvilFloat().reader());
        defer RESP3Parser.freeReply(yes, allocator);

        if (yes) |v| {
            try testing.expectEqual(@as(f32, 123.45), v.*.*.?.*);
        } else {
            unreachable;
        }
    }

    {
        const no = try RESP3Parser.parseAlloc(?***f32, allocator, MakeEvilNil().reader());
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
fn MakeEvilFloat() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream(
        ("|2\r\n" ++
            "+Ciao\r\n" ++
            "+World\r\n" ++
            "+Peach\r\n" ++
            ",9.99\r\n" ++
        ",123.45\r\n")
    [0..]);
}

fn MakeEvilNil() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream(
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
        var input = std.io.fixedBufferStream(",120.23\r\n"[0..]);
        const p1 = RESP3Parser.parse(f32, input.reader()) catch unreachable;
        try testing.expect(p1 == 120.23);
    }

    //Alloc
    const allocator = std.heap.page_allocator;
    {
        {
            const f = try RESP3Parser.parseAlloc(*f32, allocator, Make1Float().reader());
            defer allocator.destroy(f);
            try testing.expect(f.* == 120.23);
        }
        {
            const f = try RESP3Parser.parseAlloc([]f32, allocator, Make2Float().reader());
            defer allocator.free(f);
            try testing.expectEqualSlices(f32, &[_]f32{ 1.1, 2.2 }, f);
        }
    }
}

fn Make1Float() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream(",120.23\r\n"[0..]);
}

fn Make2Float() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("*2\r\n,1.1\r\n,2.2\r\n"[0..]);
}

test "optional" {
    const maybeInt: ?i64 = null;
    const maybeBool: ?bool = null;
    const maybeArr: ?[4]bool = null;
    try testing.expectEqual(maybeInt, try RESP3Parser.parse(?i64, MakeNull().reader()));
    try testing.expectEqual(maybeBool, try RESP3Parser.parse(?bool, MakeNull().reader()));
    try testing.expectEqual(maybeArr, try RESP3Parser.parse(?[4]bool, MakeNull().reader()));
}
fn MakeNull() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("_\r\n"[0..]);
}

test "array" {
    try testing.expectError(error.LengthMismatch, RESP3Parser.parse([5]i64, MakeArray().reader()));
    //try testing.expectError(error.LengthMismatch, RESP3Parser.parse([0]i64, MakeArray().reader()));
    try testing.expectError(error.UnsupportedConversion, RESP3Parser.parse([2]i64, MakeArray().reader()));
    try testing.expectEqual([2]f32{ 1.2, 3.4 }, try RESP3Parser.parse([2]f32, MakeArray().reader()));
}
fn MakeArray() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("*2\r\n,1.2\r\n,3.4\r\n"[0..]);
}

test "string" {
    try testing.expectError(error.LengthMismatch, RESP3Parser.parse([5]u8, MakeString().reader()));
    try testing.expectError(error.LengthMismatch, RESP3Parser.parse([2]u16, MakeString().reader()));
    try testing.expectEqualSlices(u8, "Hello World!", &try RESP3Parser.parse([12]u8, MakeSimpleString().reader()));
    try testing.expectError(error.LengthMismatch, RESP3Parser.parse([11]u8, MakeSimpleString().reader()));
    try testing.expectError(error.LengthMismatch, RESP3Parser.parse([13]u8, MakeSimpleString().reader()));

    const allocator = std.heap.page_allocator;
    try testing.expectEqualSlices(u8, "Banana", try RESP3Parser.parseAlloc([]u8, allocator, MakeString().reader()));
    try testing.expectEqualSlices(u8, "Hello World!", try RESP3Parser.parseAlloc([]u8, allocator, MakeSimpleString().reader()));
}
fn MakeString() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("$6\r\nBanana\r\n"[0..]);
}
fn MakeSimpleString() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("+Hello World!\r\n"[0..]);
}

test "map2struct" {
    const FixBuf = @import("./types/fixbuf.zig").FixBuf;
    const MyStruct = struct {
        first: f32,
        second: bool,
        third: FixBuf(11),
    };

    const res = try RESP3Parser.parse(MyStruct, MakeMap().reader());
    try testing.expect(res.first == 12.34);
    try testing.expect(res.second == true);
    try testing.expectEqualSlices(u8, "Hello World", res.third.toSlice());
}
test "hashmap" {
    const allocator = std.heap.page_allocator;
    const FloatDict = std.StringHashMap(f64);
    const res = try RESP3Parser.parseAlloc(FloatDict, allocator, MakeFloatMap().reader());
    try testing.expect(12.34 == res.get("aaa").?);
    try testing.expect(56.78 == res.get("bbb").?);
    try testing.expect(99.99 == res.get("ccc").?);
}
fn MakeFloatMap() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("%3\r\n$3\r\naaa\r\n,12.34\r\n$3\r\nbbb\r\n,56.78\r\n$3\r\nccc\r\n,99.99\r\n"[0..]);
}
fn MakeMap() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("%3\r\n$5\r\nfirst\r\n,12.34\r\n$6\r\nsecond\r\n#t\r\n$5\r\nthird\r\n$11\r\nHello World\r\n"[0..]);
}

test "consume right amount" {
    const FixBuf = @import("./types/fixbuf.zig").FixBuf;

    {
        var msg_err = std.io.fixedBufferStream("-ERR banana\r\n"[0..]);
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(void, msg_err.reader()));
        try testing.expectError(error.EndOfStream, (msg_err.reader()).readByte());

        msg_err.pos = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(i64, msg_err.reader()));
        try testing.expectError(error.EndOfStream, (msg_err.reader()).readByte());

        msg_err.pos = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(FixBuf(100), msg_err.reader()));
        try testing.expectError(error.EndOfStream, (msg_err.reader()).readByte());
    }

    {
        var msg_err = std.io.fixedBufferStream("!10\r\nERR banana\r\n"[0..]);
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(void, msg_err.reader()));
        try testing.expectError(error.EndOfStream, (msg_err.reader()).readByte());

        msg_err.pos = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(u64, msg_err.reader()));
        try testing.expectError(error.EndOfStream, (msg_err.reader()).readByte());

        msg_err.pos = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse([10]u8, msg_err.reader()));
        try testing.expectError(error.EndOfStream, (msg_err.reader()).readByte());
    }

    {
        var msg_err = std.io.fixedBufferStream("*2\r\n:123\r\n!10\r\nERR banana\r\n"[0..]);
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse([2]u64, msg_err.reader()));
        try testing.expectError(error.EndOfStream, (msg_err.reader()).readByte());

        const MyStruct = struct {
            a: u8,
            b: u8,
        };
        msg_err.pos = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(MyStruct, msg_err.reader()));
        try testing.expectError(error.EndOfStream, (msg_err.reader()).readByte());
    }

    {
        var msg_err = std.io.fixedBufferStream("*2\r\n:123\r\n!10\r\nERR banana\r\n"[0..]);
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse([2]u64, msg_err.reader()));
        try testing.expectError(error.EndOfStream, (msg_err.reader()).readByte());

        const MyStruct = struct {
            a: u8,
            b: u8,
        };
        msg_err.pos = 0;
        try testing.expectError(error.GotErrorReply, RESP3Parser.parse(MyStruct, msg_err.reader()));
        try testing.expectError(error.EndOfStream, (msg_err.reader()).readByte());
    }
}
