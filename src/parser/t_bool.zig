const std = @import("std");
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

    pub fn parse(comptime T: type, comptime _: type, msg: anytype) !T {
        const ch = try msg.readByte();
        try msg.skipBytes(2, .{});
        return switch (@typeInfo(T)) {
            else => unreachable,
            .bool => ch == 't',
            .int, .float => if (ch == 't') @as(T, 1) else @as(T, 0),
        };
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return isSupported(T);
    }

    pub fn parseAlloc(comptime T: type, comptime rootParser: type, allocator: std.mem.Allocator, msg: anytype) !T {
        _ = allocator;

        return parse(T, rootParser, msg);
    }
};

test "parses bools" {
    var fbs_true = TrueMSG();
    try testing.expect(true == try BoolParser.parse(bool, struct {}, fbs_true.reader()));
    var fbs_false = FalseMSG();
    try testing.expect(false == try BoolParser.parse(bool, struct {}, fbs_false.reader()));
    var fbs_true2 = TrueMSG();
    try testing.expect(1 == try BoolParser.parse(i64, struct {}, fbs_true2.reader()));
    var fbs_false2 = FalseMSG();
    try testing.expect(0 == try BoolParser.parse(u32, struct {}, fbs_false2.reader()));
    var fbs_true3 = TrueMSG();
    try testing.expect(1.0 == try BoolParser.parse(f32, struct {}, fbs_true3.reader()));
    var fbs_false3 = FalseMSG();
    try testing.expect(0.0 == try BoolParser.parse(f64, struct {}, fbs_false3.reader()));
}

// TODO: get rid of this!
fn TrueMSG() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("#t\r\n"[1..]);
}

fn FalseMSG() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("#f\r\n"[1..]);
}
