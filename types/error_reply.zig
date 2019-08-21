const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub fn OrErr(comptime T: type) type {
    return union(enum) {
        Ok: T,
        Nil: void,
        Err: struct {
            // TODO: Size based on @sizeOf(T). If we have to
            //       allocate more space anyway, let's use it.
            // TODO: How hard would it be to make different
            //       Ts based on `parse` vs `parseAlloc`?
            //       To remove `message` from the struct.
            buf: [32]u8,
            end: usize,
            message: ?[]u8,

            const Inner = @This();
            pub fn getCode(self: Inner) []u8 {
                return self.buf[0..self.end];
            }
        },

        const Self = @This();
        const Redis = struct {
            pub fn parse(tag: u8, comptime rootParser: type, msg: var) !Self {
                switch (tag) {
                    else => return Self{ .Ok = try rootParser.parseFromTag(T, tag, msg) },
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
                        for (res.Err.buf) |*elem, i| {
                            if (i == size) {
                                elem.* = ch;
                                res.Err.end = i;
                                try msg.skipBytes(2);
                                return res;
                            }
                            switch (ch) {
                                ' ' => {
                                    res.Err.end = i;
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
                        res.Err.message = null;

                        // Parse the Code part
                        var ch = try msg.readByte();
                        for (res.Err.buf) |*elem, i| {
                            switch (ch) {
                                ' ' => {
                                    res.Err.end = i;
                                    break;
                                },
                                '\r' => {
                                    res.Err.end = i;
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
                        while (ch != '\n') ch = try msg.readByte();
                        return res;
                    },
                }
            }

            pub fn parseAlloc(tag: u8, comptime rootParser: type, allocator: *Allocator, msg: var) !Self {
                switch (tag) {
                    else => return Self{ .Ok = try rootParser.parseFromTag(T, tag, msg) },
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
                        for (res.Err.buf) |*elem, i| {
                            if (i == size) {
                                elem.* = ch;
                                res.Err.end = i;
                                try msg.skipBytes(2);
                                return res;
                            }
                            switch (ch) {
                                ' ' => {
                                    res.Err.end = i;
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
                        const remainder = size - res.Err.end; // +2 because of `\r\n`
                        if (remainder == 0) return res;
                        var slice = try allocator.alloc(u8, remainder);
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
                        for (res.Err.buf) |*elem, i| {
                            switch (ch) {
                                ' ' => {
                                    res.Err.end = i;
                                    break;
                                },
                                '\r' => {
                                    res.Err.end = i;
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
}

test "parse simple errors" {
    switch (try OrErr(u8).Redis.parse('_', fakeParser, &MakeNil().stream)) {
        .Ok, .Err => unreachable,
        .Nil => testing.expect(true),
    }
    switch (try OrErr(u8).Redis.parse('!', fakeParser, &MakeBlobErr().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| testing.expectEqualSlices(u8, "ERRN\r\nOGOODFOOD", err.getCode()),
    }

    switch (try OrErr(u8).Redis.parse('-', fakeParser, &MakeErr().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| testing.expectEqualSlices(u8, "ERRNOGOODFOOD", err.getCode()),
    }

    switch (try OrErr(u8).Redis.parse('-', fakeParser, &MakeErroji().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| testing.expectEqualSlices(u8, "😈", err.getCode()),
    }

    switch (try OrErr(u8).Redis.parse('-', fakeParser, &MakeShortErr().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| testing.expectEqualSlices(u8, "ABC", err.getCode()),
    }

    testing.expectError(error.ErrorCodeBufTooSmall, OrErr(u8).Redis.parse('-', fakeParser, &MakeBadErr().stream));

    const allocator = std.heap.direct_allocator;
    switch (try OrErr(u8).Redis.parseAlloc('-', fakeParser, allocator, &MakeErroji().stream)) {
        .Ok, .Nil => unreachable,
        .Err => |err| {
            testing.expectEqualSlices(u8, "😈", err.getCode());
            testing.expectEqualSlices(u8, "your Redis belongs to us", err.message.?);
        },
    }
    switch (try OrErr(u8).Redis.parseAlloc('!', fakeParser, allocator, &MakeBlobErr().stream)) {
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
