//  SCARD key

pub const SCARD = struct {
    key: []const u8,

    /// Instantiates a new SCARD command.
    pub fn init(key: []const u8) SCARD {
        return .{ .key = key };
    }

    pub fn validate(self: SCARD) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: SCARD, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "SCARD", self.key });
        }
    };
};

test "example" {
    const cmd = SCARD.init("lol");
    try cmd.validate();
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
            SCARD.init("myset"),
        );
        try serializer.serializeCommand(
            correctMsg.writer(),
            .{ "SCARD", "myset" },
        );

        try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
