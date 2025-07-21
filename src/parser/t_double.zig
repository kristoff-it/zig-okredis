const std = @import("std");
const Reader = std.Io.Reader;
const fmt = std.fmt;
const InStream = std.io.InStream;
const builtin = @import("builtin");

/// Parses RedisDouble values (e.g. ,123.45)
pub const DoubleParser = struct {
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .float => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime _: type, r: *Reader) !T {
        const digits = try r.takeSentinel('\r');
        const result = switch (@typeInfo(T)) {
            else => unreachable,
            .float => try fmt.parseFloat(T, digits),
        };
        try r.discardAll(1);
        return result;
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return isSupported(T);
    }

    pub fn parseAlloc(
        comptime T: type,
        comptime rootParser: type,
        allocator: std.mem.Allocator,
        r: *Reader,
    ) !T {
        _ = allocator;
        return parse(T, rootParser, r);
    }
};
