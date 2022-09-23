const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const Error = struct {
    _buf: [32]u8,
    end: usize,

    /// Get the error code.
    pub fn getCode(self: Error) []const u8 {
        return self._buf[0..self.end];
    }
};

pub const FullError = struct {
    _buf: [32]u8,
    end: usize,

    /// The full error message
    message: []u8,

    /// Get the error code.
    pub fn getCode(self: FullError) []const u8 {
        return self._buf[0..self.end];
    }
};

/// Creates a union over T that is capable of optionally parsing
/// Redis Errors. It's the idiomatic way of parsing Redis errors
/// as inspectable values. `OrErr` only captures the error code,
/// use `OrFullErr` to also obtain the error message.
///
/// You can also decode `nil` replies using this union.
pub fn OrErr(comptime T: type) type {
    return union(enum) {
        Ok: T,
        Nil: void,

        /// Use `.getCode()` to obtain the error code as a `[]const u8`
        Err: Error,

        const Self = @This();
        pub const Redis = struct {
            pub const Parser = struct {
                pub const NoOptionalWrapper = true;

                pub fn parse(tag: u8, comptime rootParser: type, msg: anytype) !Self {
                    return switch (tag) {
                        '_', '-', '!' => internalParse(tag, rootParser, msg),
                        else => Self{ .Ok = try rootParser.parseFromTag(T, tag, msg) },
                    };
                }

                pub fn destroy(self: Self, comptime rootParser: type, allocator: Allocator) void {
                    switch (self) {
                        .Ok => |ok| rootParser.freeReply(ok, allocator),
                        else => {},
                    }
                }

                pub fn parseAlloc(tag: u8, comptime rootParser: type, allocator: Allocator, msg: anytype) !Self {
                    return switch (tag) {
                        '_', '-', '!' => internalParse(tag, rootParser, msg),
                        else => return Self{ .Ok = try rootParser.parseAllocFromTag(T, tag, allocator, msg) },
                    };
                }

                fn internalParse(tag: u8, comptime _: type, msg: anytype) !Self {
                    switch (tag) {
                        else => unreachable,
                        '_' => {
                            try msg.skipBytes(2, .{});
                            return Self{ .Nil = {} };
                        },
                        '!' => {
                            // TODO: write real implementation
                            var buf: [100]u8 = undefined;
                            var end: usize = 0;
                            for (buf) |*elem, i| {
                                const ch = try msg.readByte();
                                elem.* = ch;
                                if (ch == '\r') {
                                    end = i;
                                    break;
                                }
                            }

                            try msg.skipBytes(1, .{});
                            var size = try fmt.parseInt(usize, buf[0..end], 10);
                            var res = Self{ .Err = undefined };

                            // Parse the Code part
                            var ch = try msg.readByte();
                            for (res.Err._buf) |*elem, i| {
                                if (i == size) {
                                    elem.* = ch;
                                    res.Err.end = i;
                                    // res.Err.code = res.Err._buf[0..i];
                                    try msg.skipBytes(2, .{});
                                    return res;
                                }
                                switch (ch) {
                                    ' ' => {
                                        res.Err.end = i;
                                        // res.Err.code = res.Err._buf[0..i];
                                        break;
                                    },
                                    else => {
                                        elem.* = ch;
                                        ch = try msg.readByte();
                                    },
                                }
                            }

                            if (ch != ' ') return error.ErrorCodeBufTooSmall;
                            const remainder = size - res.Err.end + 2; // +2 because of `\r\n`
                            if (remainder > 0) try msg.skipBytes(remainder, .{});
                            return res;
                        },
                        '-' => {
                            var res = Self{ .Err = undefined };

                            // Parse the Code part
                            var ch = try msg.readByte();
                            for (res.Err._buf) |*elem, i| {
                                switch (ch) {
                                    ' ' => {
                                        res.Err.end = i;
                                        // res.Err.code = res.Err._buf[0..i];
                                        break;
                                    },
                                    '\r' => {
                                        res.Err.end = i;
                                        // res.Err.code = res.Err._buf[0..i];
                                        try msg.skipBytes(1, .{});
                                        return res;
                                    },
                                    else => {
                                        elem.* = ch;
                                        ch = try msg.readByte();
                                    },
                                }
                            }
                            if (ch != ' ') return error.ErrorCodeBufTooSmall;

                            // Seek through the rest of the message, discarding it.
                            while (ch != '\n') ch = try msg.readByte();
                            return res;
                        },
                    }
                }
            };
        };
    };
}

/// Like `OrErr`, but it uses an allocator to store the full error message.
pub fn OrFullErr(comptime T: type) type {
    return union(enum) {
        Ok: T,
        Nil: void,

        /// Use `.getCode()` to obtain the error code as a `[]const u8`,
        /// and `.message` to obtain the full error message as a `[]const u8`.
        Err: FullError,

        const Self = @This();
        pub const Redis = struct {
            pub const Parser = struct {
                pub const NoOptionalWrapper = true;

                pub fn parse(_: u8, comptime _: type, _: anytype) !Self {
                    @compileError("OrFullErr requires an allocator, use `OrErr` to parse just the error code without the need of an allocator.");
                }

                pub fn destroy(self: Self, comptime rootParser: type, allocator: Allocator) void {
                    switch (self) {
                        .Ok => |ok| rootParser.freeReply(ok, allocator),
                        .Err => |err| allocator.free(err.message),
                        .Nil => {},
                    }
                }

                pub fn parseAlloc(tag: u8, comptime rootParser: type, allocator: Allocator, msg: anytype) !Self {
                    switch (tag) {
                        else => return Self{ .Ok = try rootParser.parseAllocFromTag(T, tag, allocator, msg) },
                        '_' => {
                            try msg.skipBytes(2, .{});
                            return Self{ .Nil = {} };
                        },
                        '!' => {
                            // TODO: write real implementation
                            var buf: [100]u8 = undefined;
                            var end: usize = 0;
                            for (buf) |*elem, i| {
                                const ch = try msg.readByte();
                                elem.* = ch;
                                if (ch == '\r') {
                                    end = i;
                                    break;
                                }
                            }

                            try msg.skipBytes(1, .{});
                            var size = try fmt.parseInt(usize, buf[0..end], 10);
                            var res = Self{ .Err = undefined };
                            res.Err.message = &[0]u8{};

                            // Parse the Code part
                            var ch = try msg.readByte();
                            for (res.Err._buf) |*elem, i| {
                                if (i == size) {
                                    elem.* = ch;
                                    res.Err.end = i;
                                    // res.Err.code = res.Err._buf[0..i];
                                    try msg.skipBytes(2, .{});
                                    return res;
                                }
                                switch (ch) {
                                    ' ' => {
                                        res.Err.end = i;
                                        // res.Err.code = res.Err._buf[0..i];
                                        break;
                                    },
                                    else => {
                                        elem.* = ch;
                                        ch = try msg.readByte();
                                    },
                                }
                            }

                            if (ch != ' ') return error.ErrorCodeBufTooSmall;

                            // Alloc difference:
                            const remainder = size - res.Err.end;
                            if (remainder == 0) return res;
                            var slice = try allocator.alloc(u8, remainder);
                            errdefer allocator.free(slice);

                            try msg.readNoEof(slice);
                            res.Err.message = slice;
                            try msg.skipBytes(2, .{});
                            return res;
                        },
                        '-' => {
                            var res = Self{ .Err = undefined };
                            res.Err.message = &[0]u8{};

                            // Parse the Code part
                            var ch = try msg.readByte();
                            for (res.Err._buf) |*elem, i| {
                                switch (ch) {
                                    ' ' => {
                                        res.Err.end = i;
                                        // res.Err.code = res.Err._buf[0..i];
                                        break;
                                    },
                                    '\r' => {
                                        res.Err.end = i;
                                        // res.Err.code = res.Err._buf[0..i];
                                        try msg.skipBytes(1, .{});
                                        return res;
                                    },
                                    else => {
                                        elem.* = ch;
                                        ch = try msg.readByte();
                                    },
                                }
                            }
                            if (ch != ' ') return error.ErrorCodeBufTooSmall;

                            // Seek through the rest of the message,
                            // discarding it.
                            res.Err.message = try msg.readUntilDelimiterAlloc(allocator, '\r', 4096);
                            try msg.skipBytes(1, .{});
                            return res;
                        },
                    }
                }
            };
        };
    };
}
test "parse simple errors" {
    switch (try OrErr(u8).Redis.Parser.parse('_', fakeParser, MakeNil().reader())) {
        .Ok, .Err => unreachable,
        .Nil => try testing.expect(true),
    }
    switch (try OrErr(u8).Redis.Parser.parse('!', fakeParser, MakeBlobErr().reader())) {
        .Ok, .Nil => unreachable,
        .Err => |err| try testing.expectEqualSlices(u8, "ERRN\r\nOGOODFOOD", err.getCode()),
    }

    switch (try OrErr(u8).Redis.Parser.parse('-', fakeParser, MakeErr().reader())) {
        .Ok, .Nil => unreachable,
        .Err => |err| try testing.expectEqualSlices(u8, "ERRNOGOODFOOD", err.getCode()),
    }

    switch (try OrErr(u8).Redis.Parser.parse('-', fakeParser, MakeErroji().reader())) {
        .Ok, .Nil => unreachable,
        .Err => |err| try testing.expectEqualSlices(u8, "😈", err.getCode()),
    }

    switch (try OrErr(u8).Redis.Parser.parse('-', fakeParser, MakeShortErr().reader())) {
        .Ok, .Nil => unreachable,
        .Err => |err| try testing.expectEqualSlices(u8, "ABC", err.getCode()),
    }

    try testing.expectError(error.ErrorCodeBufTooSmall, OrErr(u8).Redis.Parser.parse('-', fakeParser, MakeBadErr().reader()));

    const allocator = std.heap.page_allocator;
    switch (try OrFullErr(u8).Redis.Parser.parseAlloc('-', fakeParser, allocator, MakeErroji().reader())) {
        .Ok, .Nil => unreachable,
        .Err => |err| {
            try testing.expectEqualSlices(u8, "😈", err.getCode());
            try testing.expectEqualSlices(u8, "your Redis belongs to us", err.message);
        },
    }
    switch (try OrFullErr(u8).Redis.Parser.parseAlloc('!', fakeParser, allocator, MakeBlobErr().reader())) {
        .Ok, .Nil => unreachable,
        .Err => |err| {
            try testing.expectEqualSlices(u8, "ERRN\r\nOGOODFOOD", err.getCode());
            try testing.expectEqualSlices(u8, "redis \r\n\r\ncould not find any\r\n good food", err.message);
        },
    }
}
const fakeParser = struct {
    pub inline fn parse(comptime T: type, rootParser: anytype) !T {
        _ = rootParser;
        return error.Errror;
    }
    pub inline fn parseFromTag(comptime T: type, tag: u8, rootParser: anytype) !T {
        _ = tag;
        _ = rootParser;
        return error.Errror;
    }
    pub inline fn parseAllocFromTag(comptime T: type, tag: u8, allocator: Allocator, rootParser: anytype) !T {
        _ = rootParser;
        _ = tag;
        _ = allocator;
        return error.Errror;
    }
};

fn MakeErroji() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("-😈 your Redis belongs to us\r\n"[1..]);
}
fn MakeErr() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("-ERRNOGOODFOOD redis could not find any good food\r\n"[1..]);
}
fn MakeBadErr() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("-ARIARIARIARIARIARIARIARIARIARRIVEDERCI *golden wind music starts*\r\n"[1..]);
}
fn MakeShortErr() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("-ABC\r\n"[1..]);
}
fn MakeBlobErr() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("!55\r\nERRN\r\nOGOODFOOD redis \r\n\r\ncould not find any\r\n good food\r\n"[1..]);
}
fn MakeNil() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("_\r\n"[1..]);
}

test "docs" {
    @import("std").testing.refAllDecls(@This());
    @import("std").testing.refAllDecls(Error);
    @import("std").testing.refAllDecls(FullError);
}
