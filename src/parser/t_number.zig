const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const InStream = std.io.InStream;

/// Parses RedisNumber values
pub const NumberParser = struct {
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Float, .Int => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime _: type, msg: anytype) !T {
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
        return switch (@typeInfo(T)) {
            else => unreachable,
            .Int => try fmt.parseInt(T, buf[0..end], 10),
            .Float => try fmt.parseFloat(T, buf[0..end]),
        };
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return isSupported(T);
    }

    pub fn parseAlloc(comptime T: type, comptime rootParser: type, _: std.mem.Allocator, msg: anytype) !T {
        return parse(T, rootParser, msg); // TODO: before I passed down an empty struct type. Was I insane? Did I have a plan?
    }
};
