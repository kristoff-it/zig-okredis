const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;

/// Parses RedisSimpleString values
pub const SimpleStringParser = struct {
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Int, .Float, .Array => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime _: type, msg: anytype) !T {
        switch (@typeInfo(T)) {
            else => unreachable,
            .Int => {
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
                return fmt.parseInt(T, buf[0..end], 10);
            },
            .Float => {
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
                return fmt.parseFloat(T, buf[0..end]);
            },
            .Array => |arr| {
                var res: [arr.len]arr.child = undefined;
                var bytesSlice = mem.sliceAsBytes(res[0..]);
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
            .Pointer => |ptr| switch (ptr.size) {
                .Slice, .C => ptr.child == u8, // TODO: relax constraint
                .One, .Many => false,
            },
            else => isSupported(T),
        };
    }

    pub fn parseAlloc(comptime T: type, comptime _: type, allocator: std.mem.Allocator, msg: anytype) !T {
        switch (@typeInfo(T)) {
            .Pointer => |ptr| {
                switch (ptr.size) {
                    .One, .Many => @compileError("Only Slices and C pointers should reach sub-parsers"),
                    .Slice => {
                        const bytes = try msg.readUntilDelimiterAlloc(allocator, '\r', 4096);
                        _ = std.math.divExact(usize, bytes.len, @sizeOf(ptr.child)) catch return error.LengthMismatch;
                        try msg.skipBytes(1, .{});
                        return bytes;
                    },
                    .C => {
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
