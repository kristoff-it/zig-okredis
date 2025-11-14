const std = @import("std");
const Reader = std.Io.Reader;
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;
const builtin = @import("builtin");

/// Parses RedisBlobString values
pub const BlobStringParser = struct {
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .int, .float, .array => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime _: type, r: *Reader) !T {
        const digits = try r.takeSentinel('\r');
        const size = try fmt.parseInt(usize, digits, 10);
        try r.discardAll(1);

        switch (@typeInfo(T)) {
            else => unreachable,
            .int => {
                const str_digits = try r.take(size);
                try r.discardAll(2);
                const res = try fmt.parseInt(T, str_digits, 10);
                return res;
            },
            .float => {
                const str_digits = try r.take(size);
                try r.discardAll(2);
                const res = try fmt.parseFloat(T, str_digits);
                return res;
            },
            .array => |arr| {
                var res: [arr.len]arr.child = undefined;
                const bytesSlice = mem.sliceAsBytes(res[0..]);
                if (bytesSlice.len != size) {
                    return error.LengthMismatch;
                }

                try r.readSliceAll(bytesSlice);
                try r.discardAll(2);

                return res;
            },
        }
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .pointer => true,
            else => isSupported(T),
        };
    }

    pub fn parseAlloc(comptime T: type, comptime _: type, allocator: std.mem.Allocator, r: *Reader) !T {
        // @compileLog(@typeInfo(T));
        // std.debug.print("\n\nTYPE={}\n\n", .{@typeInfo(T)});
        switch (@typeInfo(T)) {
            .pointer => |ptr| {
                const digits = try r.takeSentinel('\r');
                var size = try fmt.parseInt(usize, digits, 10);
                try r.discardAll(1);

                if (ptr.size == .c) size += @sizeOf(ptr.child);

                const elemSize = std.math.divExact(usize, size, @sizeOf(ptr.child)) catch return error.LengthMismatch;
                const res = try allocator.alignedAlloc(
                    ptr.child,
                    .fromByteUnits(ptr.alignment),
                    elemSize,
                );
                errdefer allocator.free(res);

                var bytes = mem.sliceAsBytes(res);
                if (ptr.size == .c) {
                    try r.readSliceAll(bytes[0 .. size - @sizeOf(ptr.child)]);
                    if (ptr.size == .c) {
                        // TODO: maybe reword this loop for better performance?
                        for (bytes[(size - @sizeOf(ptr.child))..]) |*b| b.* = 0;
                    }
                } else {
                    try r.readSliceAll(bytes[0..]);
                }
                try r.discardAll(2);

                return switch (ptr.size) {
                    .one, .many => @compileError("Only Slices and C pointers should reach sub-parsers"),
                    .slice => res,
                    .c => @ptrCast(res.ptr),
                };
            },
            else => return parse(T, struct {}, r),
        }
    }
};

test "string" {
    {
        var r_int = MakeInt();
        try testing.expect(1337 == try BlobStringParser.parse(
            u32,
            struct {},
            &r_int,
        ));
        var r_str = MakeString();
        try testing.expectError(error.InvalidCharacter, BlobStringParser.parse(
            u32,
            struct {},
            &r_str,
        ));
        var r_int2 = MakeInt();
        try testing.expect(1337.0 == try BlobStringParser.parse(
            f32,
            struct {},
            &r_int2,
        ));
        var r_flt = MakeFloat();
        try testing.expect(12.34 == try BlobStringParser.parse(
            f64,
            struct {},
            &r_flt,
        ));

        var r_str2 = MakeString();
        try testing.expectEqualSlices(u8, "Hello World!", &try BlobStringParser.parse(
            [12]u8,
            struct {},
            &r_str2,
        ));

        var r_ji = MakeEmoji2();
        const res = try BlobStringParser.parse([2][4]u8, struct {}, &r_ji);
        try testing.expectEqualSlices(u8, "😈", &res[0]);
        try testing.expectEqualSlices(u8, "👿", &res[1]);
    }

    {
        const allocator = std.heap.page_allocator;
        {
            var r_str3 = MakeString();
            const s = try BlobStringParser.parseAlloc(
                []u8,
                struct {},
                allocator,
                &r_str3,
            );
            defer allocator.free(s);
            try testing.expectEqualSlices(u8, s, "Hello World!");
        }
        {
            var r_str4 = MakeString();
            const s = try BlobStringParser.parseAlloc(
                [*c]u8,
                struct {},
                allocator,
                &r_str4,
            );
            defer allocator.free(s[0..12]);
            try testing.expectEqualSlices(u8, s[0..13], "Hello World!\x00");
        }
        {
            var r_ji2 = MakeEmoji2();
            const s = try BlobStringParser.parseAlloc(
                [][4]u8,
                struct {},
                allocator,
                &r_ji2,
            );
            defer allocator.free(s);
            try testing.expectEqualSlices(u8, "😈", &s[0]);
            try testing.expectEqualSlices(u8, "👿", &s[1]);
        }
        {
            var r_ji2 = MakeEmoji2();
            const s = try BlobStringParser.parseAlloc(
                [*c][4]u8,
                struct {},
                allocator,
                &r_ji2,
            );
            defer allocator.free(s[0..3]);
            try testing.expectEqualSlices(u8, "😈", &s[0]);
            try testing.expectEqualSlices(u8, "👿", &s[1]);
            try testing.expectEqualSlices(u8, &[4]u8{ 0, 0, 0, 0 }, &s[3]);
        }
        {
            var r_str4 = MakeString();
            try testing.expectError(error.LengthMismatch, BlobStringParser.parseAlloc(
                [][5]u8,
                struct {},
                allocator,
                &r_str4,
            ));
        }
    }
}

// TODO: get rid of this
fn MakeEmoji2() Reader {
    return std.Io.Reader.fixed("$8\r\n😈👿\r\n"[1..]);
}
fn MakeString() Reader {
    return std.Io.Reader.fixed("$12\r\nHello World!\r\n"[1..]);
}
fn MakeInt() Reader {
    return std.Io.Reader.fixed("$4\r\n1337\r\n"[1..]);
}
fn MakeFloat() Reader {
    return std.Io.Reader.fixed("$5\r\n12.34\r\n"[1..]);
}
