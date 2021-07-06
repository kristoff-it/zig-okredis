// SMEMBERS key

const std = @import("std");

pub const SMEMBERS = struct {
    key: []const u8,

    /// Instantiates a new SMEMBERS command.
    pub fn init(key: []const u8) SMEMBERS {
        // TODO: support std.hashmap used as a set!
        return .{ .key = key };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(_: SMEMBERS) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: SMEMBERS, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "SMEMBERS", self.key });
        }
    };
};

test "basic usage" {
    const cmd = SMEMBERS.init("myset");
    try cmd.validate();
}

test "serializer" {
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.fixedBufferStream(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.fixedBufferStream(testBuf[0..]);

    {
        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                testMsg.writer(),
                SMEMBERS.init("set1"),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SMEMBERS", "set1" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
