// SISMEMBER key member

const std = @import("std");
const Writer = std.Io.Writer;

pub const SISMEMBER = struct {
    key: []const u8,
    member: []const u8,

    /// Instantiates a new SISMEMBER command.
    pub fn init(key: []const u8, member: []const u8) SISMEMBER {
        // TODO: support std.hashmap used as a set!
        return .{ .key = key, .member = member };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(_: SISMEMBER) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(
            self: SISMEMBER,
            comptime root_serializer: type,
            w: *Writer,
        ) !void {
            return root_serializer.serializeCommand(w, .{
                "SISMEMBER",
                self.key,
                self.member,
            });
        }
    };
};

test "basic usage" {
    const cmd = SISMEMBER.init("myset", "mymember");
    try cmd.validate();
}

test "serializer" {
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.Io.Writer.fixed(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.Io.Writer.fixed(testBuf[0..]);

    {
        {
            correctMsg.end = 0;
            testMsg.end = 0;

            try serializer.serializeCommand(
                &testMsg,
                SISMEMBER.init("set1", "alice"),
            );
            try serializer.serializeCommand(
                &correctMsg,
                .{ "SISMEMBER", "set1", "alice" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(
                u8,
                correctMsg.buffered(),
                testMsg.buffered(),
            );
        }
    }
}
