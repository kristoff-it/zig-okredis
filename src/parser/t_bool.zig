const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;

/// Parses RedisBoolean values (#t and #f)
pub const BoolParser = struct {
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeId(T)) {
            .Bool, .Int, .Float => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime _: type, msg: var) !T {
        const ch = try msg.readByte();
        try msg.skipBytes(2);
        return switch (@typeId(T)) {
            .Bool => check_bool(ch),
            .Int, .Float => if (check_bool(ch)) @as(T, 1) else @as(T, 0),
            else => @compileError("Unhandled Conversion"),
        };
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Pointer => |ptr| isSupported(ptr.child),
            else => isSupported(T),
        };
    }

    pub fn parseAlloc(comptime T: type, comptime _: type, allocator: *std.mem.Allocator, msg: var) !T {
        switch (@typeInfo(T)) {
            .Pointer => |ptr| {
                var res = try allocator.alignedAlloc(ptr.child, @alignOf(T), 1);
                errdefer allocator.free(res);
                res[0] = try parse(ptr.child, struct {}, msg);
                return switch (ptr.size) {
                    .One, .Many => @compileError("Only Slices and C pointers should reach sub-parsers"),
                    .Slice => res,
                    .C => @ptrCast(T, res.ptr),
                };
            },
            else => return parse(T, struct {}, msg),
        }
    }
};

fn check_bool(ch: u8) bool {
    if (builtin.mode == .ReleaseFast) {
        return ch == 't';
    } else {
        return switch (ch) {
            't' => true,
            'f' => false,
            else => unreachable, // TODO: should this be a crash or just an error?
        };
    }
}

test "parses bools" {
    testing.expect(true == try BoolParser.parse(bool, struct {}, &TrueMSG().stream));
    testing.expect(false == try BoolParser.parse(bool, struct {}, &FalseMSG().stream));
    testing.expect(1 == try BoolParser.parse(i64, struct {}, &TrueMSG().stream));
    testing.expect(0 == try BoolParser.parse(u32, struct {}, &FalseMSG().stream));
    testing.expect(1.0 == try BoolParser.parse(f32, struct {}, &TrueMSG().stream));
    testing.expect(0.0 == try BoolParser.parse(f64, struct {}, &FalseMSG().stream));
}

fn TrueMSG() std.io.SliceInStream {
    return std.io.SliceInStream.init("#t\r\n"[1..]);
}

fn FalseMSG() std.io.SliceInStream {
    return std.io.SliceInStream.init("#f\r\n"[1..]);
}
