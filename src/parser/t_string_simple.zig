const std = @import("std");
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

    pub fn parse(comptime T: type, comptime _: type, msg: anytype) !T {
        switch (@typeInfo(T)) {
            else => unreachable,
            .int => {
                var buf: [100]u8 = undefined;
                var end: usize = 0;
                for (&buf, 0..) |*elem, i| {
                    const ch = try msg.readByte();
                    elem.* = ch;
                    if (ch == '\r') {
                        end = i;
                        break;
                    }
                }
                try msg.skipBytes(1, .{});
                return fmt.parseInt(T, buf[0..end], 10);
            },
            .float => {
                var buf: [100]u8 = undefined;
                var end: usize = 0;
                for (&buf, 0..) |*elem, i| {
                    const ch = try msg.readByte();
                    elem.* = ch;
                    if (ch == '\r') {
                        end = i;
                        break;
                    }
                }
                try msg.skipBytes(1, .{});
                return fmt.parseFloat(T, buf[0..end]);
            },
            .array => |arr| {
                var res: [arr.len]arr.child = undefined;
                const bytesSlice = mem.sliceAsBytes(res[0..]);
                var ch = try msg.readByte();
                for (bytesSlice) |*elem| {
                    if (ch == '\r') {
                        return error.LengthMismatch;
                    }
                    elem.* = ch;
                    ch = try msg.readByte();
                }
                if (ch != '\r') return error.LengthMismatch;

                try msg.skipBytes(1, .{});
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

    pub fn parseAlloc(comptime T: type, comptime _: type, allocator: std.mem.Allocator, msg: anytype) !T {
        switch (@typeInfo(T)) {
            .pointer => |ptr| {
                switch (ptr.size) {
                    .one, .many => @compileError("Only Slices and C pointers should reach sub-parsers"),
                    .slice => {
                        const bytes = try msg.readUntilDelimiterAlloc(allocator, '\r', 4096);
                        _ = std.math.divExact(usize, bytes.len, @sizeOf(ptr.child)) catch return error.LengthMismatch;
                        try msg.skipBytes(1, .{});
                        return bytes;
                    },
                    .c => {
                        // var bytes = try msg.readUntilDelimiterAlloc(allocator, '\n', 4096);
                        // res[res.len - 1] = 0;
                        // return res;
                        // TODO implement this
                        return error.Unimplemented;
                    },
                }
            },
            else => return parse(T, struct {}, msg),
        }
    }
};
