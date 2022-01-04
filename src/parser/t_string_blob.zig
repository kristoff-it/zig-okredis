const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;

/// Parses RedisBlobString values
pub const BlobStringParser = struct {
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Int, .Float, .Array => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime _: type, msg: anytype) !T {
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
        const size = try fmt.parseInt(usize, buf[0..end], 10);

        switch (@typeInfo(T)) {
            else => unreachable,
            .Int => {
                // Try to parse an int from the string.
                // TODO: write real implementation
                if (size > buf.len) return error.SorryBadImplementation;

                try msg.readNoEof(buf[0..size]);
                const res = try fmt.parseInt(T, buf[0..size], 10);
                try msg.skipBytes(2, .{});
                return res;
            },
            .Float => {
                // Try to parse a float from the string.
                // TODO: write real implementation
                if (size > buf.len) return error.SorryBadImplementation;

                try msg.readNoEof(buf[0..size]);
                const res = try fmt.parseFloat(T, buf[0..size]);
                try msg.skipBytes(2, .{});
                return res;
            },
            .Array => |arr| {
                var res: [arr.len]arr.child = undefined;
                var bytesSlice = mem.sliceAsBytes(res[0..]);
                if (bytesSlice.len != size) {
                    return error.LengthMismatch;
                }

                try msg.readNoEof(bytesSlice);
                try msg.skipBytes(2, .{});
                return res;
            },
        }
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Pointer => true,
            else => isSupported(T),
        };
    }

    pub fn parseAlloc(comptime T: type, comptime _: type, allocator: std.mem.Allocator, msg: anytype) !T {
        // @compileLog(@typeInfo(T));
        // std.debug.print("\n\nTYPE={}\n\n", .{@typeInfo(T)});
        switch (@typeInfo(T)) {
            .Pointer => |ptr| {
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

                if (ptr.size == .C) size += @sizeOf(ptr.child);

                const elemSize = std.math.divExact(usize, size, @sizeOf(ptr.child)) catch return error.LengthMismatch;
                var res = try allocator.alignedAlloc(ptr.child, @alignOf(T), elemSize);
                errdefer allocator.free(res);

                var bytes = mem.sliceAsBytes(res);
                if (ptr.size == .C) {
                    msg.readNoEof(bytes[0 .. size - @sizeOf(ptr.child)]) catch return error.GraveProtocolError;
                    if (ptr.size == .C) {
                        // TODO: maybe reword this loop for better performance?
                        for (bytes[(size - @sizeOf(ptr.child))..]) |*b| b.* = 0;
                    }
                } else {
                    msg.readNoEof(bytes[0..]) catch return error.GraveProtocolError;
                }
                try msg.skipBytes(2, .{});

                return switch (ptr.size) {
                    .One, .Many => @compileError("Only Slices and C pointers should reach sub-parsers"),
                    .Slice => res,
                    .C => @ptrCast(T, res.ptr),
                };
            },
            else => return parse(T, struct {}, msg),
        }
    }
};

test "string" {
    {
        try testing.expect(1337 == try BlobStringParser.parse(u32, struct {}, MakeInt().reader()));
        try testing.expectError(error.InvalidCharacter, BlobStringParser.parse(u32, struct {}, MakeString().reader()));
        try testing.expect(1337.0 == try BlobStringParser.parse(f32, struct {}, MakeInt().reader()));
        try testing.expect(12.34 == try BlobStringParser.parse(f64, struct {}, MakeFloat().reader()));

        try testing.expectEqualSlices(u8, "Hello World!", &try BlobStringParser.parse([12]u8, struct {}, MakeString().reader()));

        const res = try BlobStringParser.parse([2][4]u8, struct {}, MakeEmoji2().reader());
        try testing.expectEqualSlices(u8, "😈", &res[0]);
        try testing.expectEqualSlices(u8, "👿", &res[1]);
    }

    {
        const allocator = std.heap.page_allocator;
        {
            const s = try BlobStringParser.parseAlloc([]u8, struct {}, allocator, MakeString().reader());
            defer allocator.free(s);
            try testing.expectEqualSlices(u8, s, "Hello World!");
        }
        {
            const s = try BlobStringParser.parseAlloc([*c]u8, struct {}, allocator, MakeString().reader());
            defer allocator.free(s[0..12]);
            try testing.expectEqualSlices(u8, s[0..13], "Hello World!\x00");
        }
        {
            const s = try BlobStringParser.parseAlloc([][4]u8, struct {}, allocator, MakeEmoji2().reader());
            defer allocator.free(s);
            try testing.expectEqualSlices(u8, "😈", &s[0]);
            try testing.expectEqualSlices(u8, "👿", &s[1]);
        }
        {
            const s = try BlobStringParser.parseAlloc([*c][4]u8, struct {}, allocator, MakeEmoji2().reader());
            defer allocator.free(s[0..3]);
            try testing.expectEqualSlices(u8, "😈", &s[0]);
            try testing.expectEqualSlices(u8, "👿", &s[1]);
            try testing.expectEqualSlices(u8, &[4]u8{ 0, 0, 0, 0 }, &s[3]);
        }
        {
            try testing.expectError(error.LengthMismatch, BlobStringParser.parseAlloc([][5]u8, struct {}, allocator, MakeString().reader()));
        }
    }
}
fn MakeEmoji2() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("$8\r\n😈👿\r\n"[1..]);
}
fn MakeString() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("$12\r\nHello World!\r\n"[1..]);
}
fn MakeInt() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("$4\r\n1337\r\n"[1..]);
}
fn MakeFloat() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("$5\r\n12.34\r\n"[1..]);
}
