const std = @import("std");
const Reader = std.Io.Reader;
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;
const builtin = @import("builtin");

/// Parses RedisSimpleString values
pub const SimpleStringParser = struct {
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .int, .float, .array => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime _: type, r: *Reader) !T {
        switch (@typeInfo(T)) {
            else => unreachable,
            .int => {
                const digits = try r.takeSentinel('\r');
                const result = fmt.parseInt(T, digits, 10);
                try r.discardAll(1);
                return result;
            },
            .float => {
                const digits = try r.takeSentinel('\r');
                const result = fmt.parseFloat(T, digits);
                try r.discardAll(1);
                return result;
            },
            .array => |arr| {
                var res: [arr.len]arr.child = undefined;
                const bytesSlice = mem.sliceAsBytes(res[0..]);
                var ch = try r.takeByte();
                for (bytesSlice) |*elem| {
                    if (ch == '\r') {
                        return error.LengthMismatch;
                    }
                    elem.* = ch;
                    ch = try r.takeByte();
                }
                if (ch != '\r') return error.LengthMismatch;

                try r.discardAll(1);
                return res;
            },
        }
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .pointer => |ptr| switch (ptr.size) {
                .slice, .c => ptr.child == u8, // TODO: relax constraint
                .one, .many => false,
            },
            else => isSupported(T),
        };
    }

    pub fn parseAlloc(
        comptime T: type,
        comptime _: type,
        allocator: std.mem.Allocator,
        r: *Reader,
    ) !T {
        switch (@typeInfo(T)) {
            .pointer => |ptr| {
                switch (ptr.size) {
                    .one, .many => @compileError("Only Slices and C pointers should reach sub-parsers"),
                    .slice => {
                        var w: std.Io.Writer.Allocating = .init(allocator);
                        errdefer w.deinit();
                        _ = try r.streamDelimiter(&w.writer, '\r');
                        const bytes = try w.toOwnedSlice();

                        _ = std.math.divExact(usize, bytes.len, @sizeOf(ptr.child)) catch return error.LengthMismatch;
                        try r.discardAll(2);
                        return bytes;
                    },
                    .c => {
                        // var bytes = try r.readUntilDelimiterAlloc(allocator, '\n', 4096);
                        // res[res.len - 1] = 0;
                        // return res;
                        // TODO implement this
                        return error.Unimplemented;
                    },
                }
            },
            else => return parse(T, struct {}, r),
        }
    }
};
