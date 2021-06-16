//  SADD key member [member ...]

const std = @import("std");

pub const SADD = struct {
    key: []const u8,
    members: []const []const u8,

    /// Instantiates a new SADD command.
    pub fn init(key: []const u8, members: []const []const u8) SADD {
        // TODO: support std.hashmap used as a set!
        return .{ .key = key, .members = members };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: SADD) !void {
        if (self.members.len == 0) return error.MembersArrayIsEmpty;
        // TODO: should we check for duplicated members? if so, we need an allocator, methinks.
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: SADD, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "SADD", self.key, self.members });
        }
    };
};

test "basic usage" {
    const cmd = SADD.init("myset", &[_][]const u8{ "alice", "bob" });
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
                SADD.init("set1", &[_][]const u8{ "alice", "bob" }),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SADD", "set1", "alice", "bob" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
