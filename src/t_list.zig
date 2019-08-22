const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;

/// Parses RedisList values.
/// Uses RESP3Parser to delegate parsing of the list contents recursively.
pub const ListParser = struct {
    // TODO: prevent users from unmarshaling structs out of strings
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeId(T)) {
            .Void, .Array => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime rootParser: type, msg: var) anyerror!T {
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
        const size = try fmt.parseInt(usize, buf[0..end], 10);

        switch (@typeInfo(T)) {
            .Void => {
                var i: usize = 0;
                while (i < size) : (i += 1) {
                    try rootParser.parse(void, msg);
                }
            },
            .Array => |array| {
                if (array.len != size) {
                    return error.LengthMismatch;
                }
                var result: T = undefined;
                for (result) |*elem| {
                    elem.* = try rootParser.parse(array.child, msg);
                }
                return result;
            },
            else => @compileError("Unhandled Conversion"),
        }
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Array, .Pointer => true,
            else => false,
        };
    }

    pub fn parseAlloc(comptime T: type, comptime rootParser: type, allocator: *std.mem.Allocator, msg: var) !T {
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
        const size = try fmt.parseInt(usize, buf[0..end], 10);

        switch (@typeInfo(T)) {
            .Pointer => |ptr| {
                var res = try allocator.alloc(ptr.child, size);
                errdefer allocator.free(res);

                for (res) |*elem| {
                    elem.* = try rootParser.parseAlloc(ptr.child, allocator, msg);
                }

                return switch (ptr.size) {
                    .One => &res[0],
                    .Many => res.ptr,
                    .Slice => res,
                    .C => @ptrCast(T, res.ptr),
                };
            },
            .Array => |array| {
                if (array.len != size) {
                    return error.LengthMismatch;
                }
                var result: T = undefined;
                for (result) |*elem| {
                    elem.* = try rootParser.parseAlloc(array.child, allocator, msg);
                }
                return result;
            },
            else => @compileError("Unhandled Conversion"),
        }
    }
};
