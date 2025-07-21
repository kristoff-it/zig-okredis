// APPEND key value
pub const APPEND = struct {
    key: []const u8,
    value: []const u8,

    const Self = @This();

    pub fn init(key: []const u8, value: []const u8) APPEND {
        return .{ .key = key, .value = value };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
        if (self.value.len == 0) return error.EmptyValue;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: APPEND, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "APPEND", self.key, self.value });
        }
    };
};

test "example" {
    _ = APPEND.init("noun", "ism");
}

test "serializer" {
    const std = @import("std");
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.Io.Writer.fixed(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.Io.Writer.fixed(testBuf[0..]);

    {
        correctMsg.end = 0;
        testMsg.end = 0;

        try serializer.serializeCommand(
            &testMsg,
            APPEND.init("mykey", "42"),
        );
        try serializer.serializeCommand(
            &correctMsg,
            .{ "APPEND", "mykey", "42" },
        );

        try std.testing.expectEqualSlices(
            u8,
            correctMsg.buffered(),
            testMsg.buffered(),
        );
    }
}
