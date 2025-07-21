// SRANDMEMBER key [count]

const std = @import("std");

pub const SRANDMEMBER = struct {
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
    pub fn init(key: []const u8, count: Count) SRANDMEMBER {
        // TODO: support std.hashmap used as a set!
        return .{ .key = key, .count = count };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(_: SRANDMEMBER) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: SRANDMEMBER, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{
                "SRANDMEMBER",
                self.key,
                self.count,
            });
        }
    };
};

test "basic usage" {
    const cmd = SRANDMEMBER.init("myset", .one);
    try cmd.validate();

    const cmd1 = SRANDMEMBER.init("myset", SRANDMEMBER.Count{ .Count = 5 });
    try cmd1.validate();
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
                SRANDMEMBER.init("s", .one),
            );
            try serializer.serializeCommand(
                &correctMsg,
                .{ "SRANDMEMBER", "s" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.buffered(), testMsg.buffered() });
            try std.testing.expectEqualSlices(
                u8,
                correctMsg.buffered(),
                testMsg.buffered(),
            );
        }

        {
            correctMsg.end = 0;
            testMsg.end = 0;

            try serializer.serializeCommand(
                &testMsg,
                SRANDMEMBER.init("s", SRANDMEMBER.Count{ .Count = 5 }),
            );
            try serializer.serializeCommand(
                &correctMsg,
                .{ "SRANDMEMBER", "s", 5 },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.buffered(), testMsg.buffered() });
            try std.testing.expectEqualSlices(
                u8,
                correctMsg.buffered(),
                testMsg.buffered(),
            );
        }
    }
}
