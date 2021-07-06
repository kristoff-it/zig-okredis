// BITOP operation destkey key [key ...]

// TODO: implement Op as a Redis.Arguments?

pub const BITOP = struct {
    //! ```
    //! const cmd = BITOP.init(.AND, "result", &[_][]const u8{ "key1", "key2" });
    //! ```

    operation: Op,
    destKey: []const u8,
    sourceKeys: []const []const u8,

    pub fn init(operation: Op, destKey: []const u8, sourceKeys: []const []const u8) BITOP {
        return .{ .operation = operation, .destKey = destKey, .sourceKeys = sourceKeys };
    }

    pub fn validate(self: BITOP) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
        if (self.value.len == 0) return error.EmptyValue;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: BITOP, comptime rootSerializer: type, msg: anytype) !void {
            const op = switch (self.operation) {
                .AND => "AND",
                .OR => "OR",
                .XOR => "XOR",
                .NOT => "NOT",
            };
            return rootSerializer.serializeCommand(msg, .{ "BITOP", op, self.destKey, self.sourceKeys });
        }
    };

    pub const Op = enum {
        AND,
        OR,
        XOR,
        NOT,
    };
};

test "basic usage" {
    _ = BITOP.init(.AND, "result", &[_][]const u8{ "key1", "key2" });
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
            BITOP.init(.AND, "mykey", &[_][]const u8{ "key1", "key2" }),
        );
        try serializer.serializeCommand(
            correctMsg.writer(),
            .{ "BITOP", "AND", "mykey", "key1", "key2" },
        );
        try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
