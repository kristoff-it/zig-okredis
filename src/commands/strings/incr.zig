// INCR key

pub const INCR = struct {
    key: []const u8,

    pub fn init(key: []const u8) INCR {
        return .{ .key = key };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: INCR, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "INCR", self.key });
        }
    };
};

test "example" {
    const cmd = INCR.init("lol");
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
            testMsg.outStream(),
            INCR.init("mykey"),
        );
        try serializer.serializeCommand(
            correctMsg.outStream(),
            .{ "INCR", "mykey" },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
