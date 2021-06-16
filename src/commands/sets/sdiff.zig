// SDIFF key [key ...]

const std = @import("std");

pub const SDIFF = struct {
    keys: []const []const u8,

    /// Instantiates a new SDIFF command.
    pub fn init(keys: []const []const u8) SDIFF {
        return .{ .keys = keys };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: SDIFF) !void {
        if (self.keys.len == 0) return error.KeysArrayIsEmpty;
        // TODO: should we check for duplicated keys? if so, we need an allocator, methinks.
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: SDIFF, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "SDIFF", self.keys });
        }
    };
};

test "basic usage" {
    const cmd = SDIFF.init(&[_][]const u8{ "set1", "set2" });
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
                SDIFF.init(&[_][]const u8{ "set1", "set2" }),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SDIFF", "set1", "set2" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
