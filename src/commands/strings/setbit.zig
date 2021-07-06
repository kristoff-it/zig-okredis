// SETBIT key offset value
const Value = @import("../_common_utils.zig").Value;

pub const SETBIT = struct {
    //! ```
    //! const cmd1 = SETBIT.init("lol", 100, 42);
    //! const cmd2 = SETBIT.init("lol", 100, "banana");
    //! ```

    key: []const u8,
    offset: usize,
    value: Value,

    pub fn init(key: []const u8, offset: usize, value: anytype) SETBIT {
        return .{ .key = key, .offset = offset, .value = Value.fromVar(value) };
    }

    pub fn validate(self: SETBIT) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: SETBIT, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "SETBIT", self.key, self.offset, self.value });
        }
    };
};

test "basic usage" {
    _ = SETBIT.init("lol", 100, "banana");
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
            SETBIT.init("mykey", 1, 99),
        );
        try serializer.serializeCommand(
            correctMsg.writer(),
            .{ "SETBIT", "mykey", 1, 99 },
        );

        try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
