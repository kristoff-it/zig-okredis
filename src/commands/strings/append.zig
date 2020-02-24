// APPEND key value
pub const APPEND = struct {
    key: []const u8,
    value: []const u8,

    pub fn init(key: []const u8, value: []const u8) APPEND {
        return .{ .key = key, .value = value };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
        if (self.value.len == 0) return error.EmptyValue;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: APPEND, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "APPEND", self.key, self.value });
        }
    };
};

test "example" {
    const cmd = APPEND.init("noun", "ism");
}

test "serializer" {
    const std = @import("std");
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.SliceOutStream.init(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.SliceOutStream.init(testBuf[0..]);

    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            APPEND.init("mykey", "42"),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "APPEND", "mykey", "42" },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
