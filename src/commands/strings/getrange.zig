// GETRANGE key start end

pub const GETRANGE = struct {
    key: []const u8,
    start: isize,
    end: isize,

    const Self = @This();

    pub fn init(key: []const u8, start: isize, end: isize) GETRANGE {
        return .{ .key = key, .start = start, .end = end };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: GETRANGE, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "GETRANGE", self.key, self.start, self.end });
        }
    };
};

test "basic usage" {
    _ = GETRANGE.init("lol", 5, 100);
}

test "serializer" {
    const std = @import("std");
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.Io.Writer.fixed(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.Io.Writer.fixed(testBuf[0..]);

    {
        correctMsg.end = 0;
        testMsg.end = 0;

        try serializer.serializeCommand(
            &testMsg,
            GETRANGE.init("mykey", 1, 99),
        );
        try serializer.serializeCommand(
            &correctMsg,
            .{ "GETRANGE", "mykey", 1, 99 },
        );

        try std.testing.expectEqualSlices(
            u8,
            correctMsg.buffered(),
            testMsg.buffered(),
        );
    }
}
