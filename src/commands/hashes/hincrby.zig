// HINCRBY key field increment

pub const HINCRBY = struct {
    key: []const u8,
    field: []const u8,
    increment: i64,

    pub fn init(key: []const u8, field: []const u8, increment: i64) HINCRBY {
        return .{ .key = key, .field = field, .increment = increment };
    }

    pub fn validate(_: HINCRBY) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: HINCRBY, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{
                "HINCRBY",
                self.key,
                self.field,
                self.increment,
            });
        }
    };
};

test "basic usage" {
    _ = HINCRBY.init("hashname", "fieldname", 42);
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
            HINCRBY.init("mykey", "myfield", 42),
        );
        try serializer.serializeCommand(
            correctMsg.writer(),
            .{ "HINCRBY", "mykey", "myfield", 42 },
        );

        try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
