// INCRBYFLOAT key increment
pub const INCRBYFLOAT = struct {
    key: []const u8,
    increment: f64,

    const Self = @This();

    pub fn init(key: []const u8, increment: f64) INCRBYFLOAT {
        return .{ .key = key, .increment = increment };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: INCRBYFLOAT, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "INCRBYFLOAT", self.key, self.increment });
        }
    };
};

test "basic usage" {
    _ = INCRBYFLOAT.init("lol", 42);
}

test "serializer" {
    const std = @import("std");
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.fixedBufferStream(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.fixedBufferStream(testBuf[0..]);

    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            testMsg.writer(),
            INCRBYFLOAT.init("mykey", 42.1337),
        );
        try serializer.serializeCommand(
            correctMsg.writer(),
            .{ "INCRBYFLOAT", "mykey", 42.1337 },
        );

        try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
