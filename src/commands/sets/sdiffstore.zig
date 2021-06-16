// SDIFFSTORE destination key [key ...]

const std = @import("std");

pub const SDIFFSTORE = struct {
    destination: []const u8,
    keys: []const []const u8,

    /// Instantiates a new SDIFFSTORE command.
    pub fn init(destination: []const u8, keys: []const []const u8) SDIFFSTORE {
        // TODO: support std.hashmap used as a set!
        return .{ .destination = destination, .keys = keys };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: SDIFFSTORE) !void {
        if (self.keys.len == 0) return error.KeysArrayIsEmpty;
        // TODO: should we check for duplicated members? if so, we need an allocator, methinks.
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: SDIFFSTORE, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "SDIFFSTORE", self.destination, self.keys });
        }
    };
};

test "basic usage" {
    const cmd = SDIFFSTORE.init("finalSet", &[_][]const u8{ "set1", "set2" });
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
                SDIFFSTORE.init("destination", &[_][]const u8{ "set1", "set2" }),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SDIFFSTORE", "destination", "set1", "set2" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
