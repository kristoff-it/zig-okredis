const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const InStream = std.io.InStream;

/// Parses RedisDouble values (e.g. ,123.45)
pub const DoubleParser = struct {
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeId(T)) {
            .Float => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime _: type, msg: var) !T {
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
        return switch (@typeInfo(T)) {
            .Float => try fmt.parseFloat(T, buf[0..end]),
            else => @compileError("Unhandled Conversion"),
        };
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return isSupported(T);
    }

    pub fn parseAlloc(comptime T: type, comptime _: type, allocator: *std.mem.Allocator, msg: var) !T {
        return parse(T, struct {}, msg);
    }
};
