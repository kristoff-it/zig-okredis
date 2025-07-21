const std = @import("std");
const Reader = std.Io.Reader;
const fmt = std.fmt;
const testing = std.testing;
const builtin = @import("builtin");

pub const BoolParser = struct {
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .bool, .int, .float => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime _: type, r: *Reader) !T {
        const ch = try r.takeByte();
        try r.discardAll(2);
        return switch (@typeInfo(T)) {
            else => unreachable,
            .bool => ch == 't',
            .int, .float => if (ch == 't') @as(T, 1) else @as(T, 0),
        };
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return isSupported(T);
    }

    pub fn parseAlloc(comptime T: type, comptime rootParser: type, allocator: std.mem.Allocator, r: *Reader) !T {
        _ = allocator;

        return parse(T, rootParser, r);
    }
};

test "parses bools" {
    var r_true = Truer();
    try testing.expect(true == try BoolParser.parse(bool, struct {}, &r_true));
    var r_false = Falser();
    try testing.expect(false == try BoolParser.parse(bool, struct {}, &r_false));
    var r_true2 = Truer();
    try testing.expect(1 == try BoolParser.parse(i64, struct {}, &r_true2));
    var r_false2 = Falser();
    try testing.expect(0 == try BoolParser.parse(u32, struct {}, &r_false2));
    var r_true3 = Truer();
    try testing.expect(1.0 == try BoolParser.parse(f32, struct {}, &r_true3));
    var r_false3 = Falser();
    try testing.expect(0.0 == try BoolParser.parse(f64, struct {}, &r_false3));
}

// TODO: get rid of this!
fn Truer() Reader {
    return std.Io.Reader.fixed("#t\r\n"[1..]);
}

fn Falser() Reader {
    return std.Io.Reader.fixed("#f\r\n"[1..]);
}
