// SPOP key [count]

const std = @import("std");

pub const SPOP = struct {
    key: []const u8,
    count: Count,

    pub const Count = union(enum) {
        one,
        Count: usize,

        pub const RedisArguments = struct {
            pub fn count(self: Count) usize {
                return switch (self) {
                    .one => 0,
                    .Count => 1,
                };
            }

            pub fn serialize(self: Count, comptime rootSerializer: type, msg: anytype) !void {
                switch (self) {
                    .one => {},
                    .Count => |c| {
                        try rootSerializer.serializeArgument(msg, usize, c);
                    },
                }
            }
        };
    };

    /// Instantiates a new SPOP command.
    pub fn init(key: []const u8, count: Count) SPOP {
        // TODO: support std.hashmap used as a set!
        return .{ .key = key, .count = count };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(_: SPOP) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: SPOP, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{
                "SPOP",
                self.key,
                self.count,
            });
        }
    };
};

test "basic usage" {
    const cmd = SPOP.init("myset", .one);
    try cmd.validate();

    const cmd1 = SPOP.init("myset", SPOP.Count{ .Count = 5 });
    try cmd1.validate();
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
                SPOP.init("s", .one),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SPOP", "s" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                testMsg.writer(),
                SPOP.init("s", SPOP.Count{ .Count = 5 }),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SPOP", "s", 5 },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
