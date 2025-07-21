const std = @import("std");
const Reader = std.Io.Reader;
const fmt = std.fmt;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const Error = struct {
    _buf: [32]u8,
    end: usize,

    /// Get the error code.
    pub fn getCode(self: *const Error) []const u8 {
        return self._buf[0..self.end];
    }
};

pub const FullError = struct {
    _buf: [32]u8,
    end: usize,

    /// The full error message
    message: []u8,

    /// Get the error code.
    pub fn getCode(self: *const FullError) []const u8 {
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

                pub fn parse(
                    tag: u8,
                    comptime rootParser: type,
                    r: *Reader,
                ) !Self {
                    return switch (tag) {
                        '_', '-', '!' => internalParse(tag, rootParser, r),
                        else => Self{ .Ok = try rootParser.parseFromTag(T, tag, r) },
                    };
                }

                pub fn destroy(
                    self: Self,
                    comptime rootParser: type,
                    allocator: Allocator,
                ) void {
                    switch (self) {
                        .Ok => |ok| rootParser.freeReply(ok, allocator),
                        else => {},
                    }
                }

                pub fn parseAlloc(
                    tag: u8,
                    comptime rootParser: type,
                    allocator: Allocator,
                    r: *Reader,
                ) !Self {
                    return switch (tag) {
                        '_', '-', '!' => internalParse(tag, rootParser, r),
                        else => return Self{
                            .Ok = try rootParser.parseAllocFromTag(
                                T,
                                tag,
                                allocator,
                                r,
                            ),
                        },
                    };
                }

                fn internalParse(tag: u8, comptime _: type, r: *Reader) !Self {
                    switch (tag) {
                        else => unreachable,
                        '_' => {
                            try r.discardAll(2);
                            return Self{ .Nil = {} };
                        },
                        '!' => {
                            const digits = try r.takeSentinel('\r');
                            const size = try fmt.parseInt(usize, digits, 10);
                            try r.discardAll(1);

                            var res = Self{ .Err = undefined };

                            // Parse the Code part
                            var code_w = std.Io.Writer.fixed(&res.Err._buf);
                            res.Err.end = try r.streamDelimiter(&code_w, ' ');
                            r.toss(1);

                            const remainder = size - res.Err.end + 2; // +2 because of `\r\n`
                            try r.discardAll(remainder);
                            return res;
                        },
                        '-' => {
                            var res = Self{ .Err = undefined };

                            // Parse the Code part
                            var code_w = std.Io.Writer.fixed(&res.Err._buf);
                            res.Err.end = try r.streamDelimiter(&code_w, ' ');
                            r.toss(1);

                            // Seek through the rest of the message, discarding it.
                            _ = try r.discardDelimiterInclusive('\n');
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

                pub fn parseAlloc(
                    tag: u8,
                    comptime rootParser: type,
                    allocator: Allocator,
                    r: *Reader,
                ) !Self {
                    switch (tag) {
                        else => return Self{ .Ok = try rootParser.parseAllocFromTag(T, tag, allocator, r) },
                        '_' => {
                            try r.discardAll(2);
                            return Self{ .Nil = {} };
                        },
                        '!' => {
                            const digits = try r.takeSentinel('\r');
                            const size = try fmt.parseInt(usize, digits, 10);
                            try r.discardAll(1);

                            var res = Self{ .Err = undefined };
                            res.Err.message = &[0]u8{};

                            // Parse the Code part
                            var code_w = std.Io.Writer.fixed(&res.Err._buf);
                            res.Err.end = try r.streamDelimiter(&code_w, ' ');
                            r.toss(1);

                            // Alloc difference:
                            const remainder = size - res.Err.end;
                            if (remainder == 0) return res;
                            const slice = try allocator.alloc(u8, remainder);
                            errdefer allocator.free(slice);

                            try r.readSliceAll(slice);
                            res.Err.message = slice;
                            try r.discardAll(2);
                            return res;
                        },
                        '-' => {
                            var res = Self{ .Err = undefined };
                            res.Err.message = &[0]u8{};

                            // Parse the Code part
                            var code_w = std.Io.Writer.fixed(&res.Err._buf);
                            res.Err.end = try r.streamDelimiter(&code_w, ' ');
                            r.toss(1);

                            var msg_w: std.Io.Writer.Allocating = .init(allocator);
                            errdefer msg_w.deinit();
                            _ = try r.streamDelimiter(&msg_w.writer, '\r');

                            res.Err.message = try msg_w.toOwnedSlice();
                            try r.discardAll(2);
                            return res;
                        },
                    }
                }
            };
        };
    };
}
test "parse simple errors" {
    var nil = MakeNil();
    switch (try OrErr(u8).Redis.Parser.parse('_', fakeParser, &nil)) {
        .Ok, .Err => unreachable,
        .Nil => try testing.expect(true),
    }
    var blob = MakeBlobErr();
    switch (try OrErr(u8).Redis.Parser.parse('!', fakeParser, &blob)) {
        .Ok, .Nil => unreachable,
        .Err => |err| try testing.expectEqualSlices(
            u8,
            "ERRN\r\nOGOODFOOD",
            err.getCode(),
        ),
    }

    var r_err = MakeErr();
    switch (try OrErr(u8).Redis.Parser.parse('-', fakeParser, &r_err)) {
        .Ok, .Nil => unreachable,
        .Err => |err| try testing.expectEqualSlices(
            u8,
            "ERRNOGOODFOOD",
            err.getCode(),
        ),
    }

    var errji = MakeErroji();
    switch (try OrErr(u8).Redis.Parser.parse('-', fakeParser, &errji)) {
        .Ok, .Nil => unreachable,
        .Err => |err| try testing.expectEqualSlices(u8, "😈", err.getCode()),
    }

    var short_err = MakeShortErr();
    switch (try OrErr(u8).Redis.Parser.parse('-', fakeParser, &short_err)) {
        .Ok, .Nil => unreachable,
        .Err => |err| try testing.expectEqualSlices(u8, "ABC", err.getCode()),
    }

    var bad_err = MakeBadErr();
    try testing.expectError(
        error.WriteFailed,
        OrErr(u8).Redis.Parser.parse('-', fakeParser, &bad_err),
    );

    const allocator = std.heap.page_allocator;
    var errji2 = MakeErroji();
    switch (try OrFullErr(u8).Redis.Parser.parseAlloc(
        '-',
        fakeParser,
        allocator,
        &errji2,
    )) {
        .Ok, .Nil => unreachable,
        .Err => |err| {
            try testing.expectEqualSlices(u8, "😈", err.getCode());
            try testing.expectEqualSlices(u8, "your Redis belongs to us", err.message);
        },
    }
    var blob2 = MakeBlobErr();
    switch (try OrFullErr(u8).Redis.Parser.parseAlloc(
        '!',
        fakeParser,
        allocator,
        &blob2,
    )) {
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

// TODO: get rid of this!!!
fn MakeErroji() Reader {
    return std.Io.Reader.fixed("-😈 your Redis belongs to us\r\n"[1..]);
}
fn MakeErr() Reader {
    return std.Io.Reader.fixed("-ERRNOGOODFOOD redis could not find any good food\r\n"[1..]);
}
fn MakeBadErr() Reader {
    return std.Io.Reader.fixed("-ARIARIARIARIARIARIARIARIARIARRIVEDERCI *golden wind music starts*\r\n"[1..]);
}
fn MakeShortErr() Reader {
    return std.Io.Reader.fixed("-ABC shortmsg\r\n"[1..]);
}
fn MakeBlobErr() Reader {
    return std.Io.Reader.fixed("!55\r\nERRN\r\nOGOODFOOD redis \r\n\r\ncould not find any\r\n good food\r\n"[1..]);
}
fn MakeNil() Reader {
    return std.Io.Reader.fixed("_\r\n"[1..]);
}

test "docs" {
    @import("std").testing.refAllDecls(@This());
    @import("std").testing.refAllDecls(Error);
    @import("std").testing.refAllDecls(FullError);
}
