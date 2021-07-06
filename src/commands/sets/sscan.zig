// SSCAN key cursor [MATCH pattern] [COUNT count]
const std = @import("std");

pub const SSCAN = struct {
    key: []const u8,
    cursor: []const u8,
    pattern: Pattern,
    count: Count,

    pub const Pattern = union(enum) {
        NoPattern,
        Pattern: []const u8,

        pub const RedisArguments = struct {
            pub fn count(self: Pattern) usize {
                return switch (self) {
                    .NoPattern => 0,
                    .Pattern => 2,
                };
            }

            pub fn serialize(self: Pattern, comptime rootSerializer: type, msg: anytype) !void {
                switch (self) {
                    .NoPattern => {},
                    .Pattern => |p| {
                        try rootSerializer.serializeArgument(msg, []const u8, "MATCH");
                        try rootSerializer.serializeArgument(msg, []const u8, p);
                    },
                }
            }
        };
    };

    pub const Count = union(enum) {
        NoCount,
        Count: usize,

        pub const RedisArguments = struct {
            pub fn count(self: Count) usize {
                return switch (self) {
                    .NoCount => 0,
                    .Count => 2,
                };
            }

            pub fn serialize(self: Count, comptime rootSerializer: type, msg: anytype) !void {
                switch (self) {
                    .NoCount => {},
                    .Count => |c| {
                        try rootSerializer.serializeArgument(msg, []const u8, "COUNT");
                        try rootSerializer.serializeArgument(msg, usize, c);
                    },
                }
            }
        };
    };

    /// Instantiates a new SPOP command.
    pub fn init(key: []const u8, cursor: []const u8, pattern: Pattern, count: Count) SSCAN {
        // TODO: support std.hashmap used as a set!
        return .{ .key = key, .cursor = cursor, .pattern = pattern, .count = count };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(_: SSCAN) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: SSCAN, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{
                "SSCAN",
                self.key,
                self.cursor,
                self.pattern,
                self.count,
            });
        }
    };
};

test "basic usage" {
    const cmd = SSCAN.init("myset", "0", .NoPattern, .NoCount);
    try cmd.validate();

    const cmd1 = SSCAN.init("myset", "0", SSCAN.Pattern{ .Pattern = "zig_*" }, SSCAN.Count{ .Count = 5 });
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
                SSCAN.init("myset", "0", .NoPattern, .NoCount),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SSCAN", "myset", "0" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                testMsg.writer(),
                SSCAN.init("myset", "0", SSCAN.Pattern{ .Pattern = "zig_*" }, SSCAN.Count{ .Count = 5 }),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SSCAN", "myset", 0, "MATCH", "zig_*", "COUNT", 5 },
            );

            // std.debug.warn("\n{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
