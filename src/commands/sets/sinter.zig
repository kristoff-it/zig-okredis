// SINTER key [key ...]

const std = @import("std");

pub const SINTER = struct {
    keys: []const []const u8,

    /// Instantiates a new SINTER command.
    pub fn init(keys: []const []const u8) SINTER {
        return .{ .keys = keys };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: SINTER) !void {
        if (self.keys.len == 0) return error.KeysArrayIsEmpty;
        // TODO: should we check for duplicated keys? if so, we need an allocator, methinks.
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: SINTER, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "SINTER", self.keys });
        }
    };
};

test "basic usage" {
    const cmd = SINTER.init(&[_][]const u8{ "set1", "set2" });
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
                SINTER.init(&[_][]const u8{ "set1", "set2" }),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SINTER", "set1", "set2" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
