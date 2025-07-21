const std = @import("std");
const Reader = std.Io.Reader;
const fmt = std.fmt;
const InStream = std.io.InStream;
const builtin = @import("builtin");

/// Parses RedisNumber values
pub const NumberParser = struct {
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .float, .int => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime _: type, r: *Reader) !T {
        const digits = try r.takeSentinel('\r');
        const result = switch (@typeInfo(T)) {
            else => unreachable,
            .int => try fmt.parseInt(T, digits, 10),
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
        _: std.mem.Allocator,
        r: *Reader,
    ) !T {
        return parse(T, rootParser, r); // TODO: before I passed down an empty struct type. Was I insane? Did I have a plan?
    }
};
