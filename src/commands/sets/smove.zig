// SMOVE source destination member

const std = @import("std");

pub const SMOVE = struct {
    source: []const u8,
    destination: []const u8,
    member: []const u8,

    /// Instantiates a new SMOVE command.
    pub fn init(source: []const u8, destination: []const u8, member: []const u8) SMOVE {
        // TODO: support std.hashmap used as a set!
        return .{ .source = source, .destination = destination, .member = member };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: SMOVE) !void {
        // TODO: maybe this check is dumb and we shouldn't have it
        if (std.mem.eql(u8, self.source, self.destination)) {
            return error.SameSourceAndDestination;
        }
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: SMOVE, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{
                "SMOVE",
                self.source,
                self.destination,
                self.member,
            });
        }
    };
};

test "basic usage" {
    const cmd = SMOVE.init("source", "destination", "element");
    try cmd.validate();

    const cmd1 = SMOVE.init("source", "source", "element");
    try std.testing.expectError(error.SameSourceAndDestination, cmd1.validate());
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
                SMOVE.init("s", "d", "m"),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SMOVE", "s", "d", "m" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
