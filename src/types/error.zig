const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const Error = struct {
    // TODO: Size based on @sizeOf(T). If we have to
    //       allocate more space anyway, let's use it.
    _buf: [32]u8,
    end: usize,

    const Self = @This();
    pub fn getCode(self: Self) []u8 {
        return self._buf[0..self.end];
    }
};

pub const FullError = struct {
    // TODO: Size based on @sizeOf(T). If we have to
    //       allocate more space anyway, let's use it.
    // TODO: How hard would it be to make different
    //       Ts based on `parse` vs `parseAlloc`?
    //       To remove `message` from the struct.
    _buf: [32]u8,
    end: usize,
    message: ?[]u8,

    const Self = @This();
    pub fn getCode(self: Self) []u8 {
        return self._buf[0..self.end];
    }
};

/// Creates a union over T that is capable of optionally parsing
/// Redis Errors. It's the only way to successfully decode a
/// server error, in order to ensure that error replies don't
/// get silently ignored. In other words, the main parser
/// always errors out when trying to parse Redis Error replies.
pub fn OrErr(comptime T: type) type {
    return union(enum) {
        Ok: T,
        Nil: void,
        Err: Error,

        const Self = @This();
        pub const Redis = struct {
            pub const Parser = struct {
                pub fn parse(tag: u8, comptime rootParser: type, msg: var) !Self {
                    return switch (tag) {
                        '_', '-', '!' => internalParse(tag, rootParser, msg),
                        else => Self{ .Ok = try rootParser.parseFromTag(T, tag, msg) },
                    };
                }

                pub fn destroy(self: Self, comptime rootParser: type, allocator: *Allocator) void {
                    switch (self) {
                        .Ok => |ok| rootParser.freeReply(ok, allocator),
                        else => {},
                    }
                }

                pub fn parseAlloc(tag: u8, comptime rootParser: type, allocator: *Allocator, msg: var) !Self {
                    return switch (tag) {
                        '_', '-', '!' => internalParse(tag, rootParser, msg),
                        else => return Self{ .Ok = try rootParser.parseAllocFromTag(T, tag, allocator, msg) },
                    };
                }

                fn internalParse(tag: u8, comptime rootParser: type, msg: var) !Self {
                    switch (tag) {
                        else => unreachable,
                        '_' => {
                            try msg.skipBytes(2);
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

                            try msg.skipBytes(1);
                            var size = try fmt.parseInt(usize, buf[0..end], 10);
                            var res = Self{ .Err = undefined };

                            // Parse the Code part
                            var ch = try msg.readByte();
                            for (res.Err._buf) |*elem, i| {
                                if (i == size) {
                                    elem.* = ch;
                                    res.Err.end = i;
                                    // res.Err.code = res.Err._buf[0..i];
                                    try msg.skipBytes(2);
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
                            if (remainder > 0) try msg.skipBytes(remainder);
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
                                        try msg.skipBytes(1);
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

// Like OrErr, but it uses an allocator to store the msg error message
pub fn OrFullErr(comptime T: type) type {
    return union(enum) {
        Ok: T,
        Nil: void,
        Err: FullError,

        const Self = @This();
        pub const Redis = struct {
            pub const Parser = struct {
                pub fn parse(tag: u8, comptime rootParser: type, msg: var) !Self {
                    @compileError("OrFullErr requires an allocator, use `OrErr` to parse just the error code without the need of an allocator.");
                }

                pub fn destroy(self: Self, comptime rootParser: type, allocator: *Allocator) void {
                    switch (self) {
                        .Ok => |ok| rootParser.freeReply(ok, allocator),
                        .Err => |err| if (err.message) |msg| allocator.free(msg),
                        .Nil => {},
                    }
                }

                pub fn parseAlloc(tag: u8, comptime rootParser: type, allocator: *Allocator, msg: var) !Self {
                    switch (tag) {
                        else => return Self{ .Ok = try rootParser.parseAllocFromTag(T, tag, allocator, msg) },
                        '_' => {
                            try msg.skipBytes(2);
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

                            try msg.skipBytes(1);
                            var size = try fmt.parseInt(usize, buf[0..end], 10);
                            var res = Self{ .Err = undefined };
                            res.Err.message = null;

                            // Parse the Code part
                            var ch = try msg.readByte();
                            for (res.Err._buf) |*elem, i| {
                                if (i == size) {
                                    elem.* = ch;
                                    res.Err.end = i;
                                    // res.Err.code = res.Err._buf[0..i];
                                    try msg.skipBytes(2);
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
                            try msg.skipBytes(2);
                            return res;
                        },
                        '-' => {
                            var res = Self{ .Err = undefined };
                            res.Err.message = null;

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
                                        try msg.skipBytes(1);
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
                            try msg.skipBytes(1);
                            return res;
                        },
                    }
                }
            };
        };
    };
}
test "parse simple errors" {
    switch (try OrErr(u8).Redis.Parser.parse('_', fakeParser, &MakeNil().stream)) {
        .Ok, .Err => unreachable,
        .Nil => testing.expect(true),
    }
    switch (try OrErr(u8).Redis.Parser.parse('!', fakeParser, &MakeBlobErr().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| testing.expectEqualSlices(u8, "ERRN\r\nOGOODFOOD", err.getCode()),
    }

    switch (try OrErr(u8).Redis.Parser.parse('-', fakeParser, &MakeErr().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| testing.expectEqualSlices(u8, "ERRNOGOODFOOD", err.getCode()),
    }

    switch (try OrErr(u8).Redis.Parser.parse('-', fakeParser, &MakeErroji().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| testing.expectEqualSlices(u8, "😈", err.getCode()),
    }

    switch (try OrErr(u8).Redis.Parser.parse('-', fakeParser, &MakeShortErr().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| testing.expectEqualSlices(u8, "ABC", err.getCode()),
    }

    testing.expectError(error.ErrorCodeBufTooSmall, OrErr(u8).Redis.Parser.parse('-', fakeParser, &MakeBadErr().stream));

    const allocator = std.heap.direct_allocator;
    switch (try OrFullErr(u8).Redis.Parser.parseAlloc('-', fakeParser, allocator, &MakeErroji().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| {
            testing.expectEqualSlices(u8, "😈", err.getCode());
            testing.expectEqualSlices(u8, "your Redis belongs to us", err.message.?);
        },
    }
    switch (try OrFullErr(u8).Redis.Parser.parseAlloc('!', fakeParser, allocator, &MakeBlobErr().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| {
            testing.expectEqualSlices(u8, "ERRN\r\nOGOODFOOD", err.getCode());
            testing.expectEqualSlices(u8, "redis \r\n\r\ncould not find any\r\n good food", err.message.?);
        },
    }
}
const fakeParser = struct {
    pub inline fn parse(comptime T: type, msg: var) !T {
        return error.Errror;
    }
    pub inline fn parseFromTag(comptime T: type, tag: u8, msg: var) !T {
        return error.Errror;
    }
    pub inline fn parseAllocFromTag(comptime T: type, tag: u8, allocator: *Allocator, msg: var) !T {
        return error.Errror;
    }
};

fn MakeErroji() std.io.SliceInStream {
    return std.io.SliceInStream.init("😈 your Redis belongs to us\r\n"[0..]);
}
fn MakeErr() std.io.SliceInStream {
    return std.io.SliceInStream.init("ERRNOGOODFOOD redis could not find any good food\r\n"[0..]);
}
fn MakeBadErr() std.io.SliceInStream {
    return std.io.SliceInStream.init("ARIARIARIARIARIARIARIARIARIARRIVEDERCI *golden wind music starts*\r\n"[0..]);
}
fn MakeShortErr() std.io.SliceInStream {
    return std.io.SliceInStream.init("ABC\r\n"[0..]);
}
fn MakeBlobErr() std.io.SliceInStream {
    return std.io.SliceInStream.init("55\r\nERRN\r\nOGOODFOOD redis \r\n\r\ncould not find any\r\n good food\r\n"[0..]);
}
fn MakeNil() std.io.SliceInStream {
    return std.io.SliceInStream.init("\r\n"[0..]);
}
