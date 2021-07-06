// XTRIM key MAXLEN [~] count

pub const XTRIM = struct {
    key: []const u8,
    strategy: Strategy,

    /// Instantiates a new XTRIM command.
    pub fn init(key: []const u8, strategy: Strategy) XTRIM {
        return .{ .key = key, .strategy = strategy };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: XTRIM) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: XTRIM, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "XTRIM", self.key, self.strategy });
        }
    };

    pub const Strategy = union(enum) {
        MaxLen: struct {
            precise: bool = false,
            count: u64,
        },

        pub const RedisArguments = struct {
            pub fn count(self: Strategy) usize {
                switch (self) {
                    .MaxLen => |m| if (!m.precise) {
                        return 3;
                    } else {
                        return 2;
                    },
                }
            }

            pub fn serialize(self: Strategy, comptime rootSerializer: type, msg: anytype) !void {
                switch (self) {
                    .MaxLen => |m| {
                        try rootSerializer.serializeArgument(msg, []const u8, "MAXLEN");
                        if (!m.precise) try rootSerializer.serializeArgument(msg, []const u8, "~");
                        try rootSerializer.serializeArgument(msg, u64, m.count);
                    },
                }
            }
        };
    };
};

test "basic usage" {
    _ = XTRIM.init("mykey", XTRIM.Strategy{ .MaxLen = .{ .count = 10 } });
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
            XTRIM.init("mykey", XTRIM.Strategy{ .MaxLen = .{ .count = 30 } }),
        );
        try serializer.serializeCommand(
            correctMsg.writer(),
            .{ "XTRIM", "mykey", "MAXLEN", "~", 30 },
        );

        try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
