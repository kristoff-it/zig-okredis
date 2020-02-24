// INCRBY key increment
pub const INCRBY = struct {
    key: []const u8,
    increment: i64,

    pub fn init(key: []const u8, increment: i64) INCRBY {
        return .{ .key = key, .increment = increment };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: INCRBY, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "INCRBY", self.key, self.increment });
        }
    };
};

test "basic usage" {
    const cmd = INCRBY.init("lol", 42);
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
            INCRBY.init("mykey", 42),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "INCRBY", "mykey", 42 },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
