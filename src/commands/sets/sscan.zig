// SSCAN key cursor [MATCH pattern] [COUNT count]

const std = @import("std");
const Writer = std.Io.Writer;

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

            pub fn serialize(
                self: Pattern,
                comptime root: type,
                w: *Writer,
            ) !void {
                switch (self) {
                    .NoPattern => {},
                    .Pattern => |p| {
                        try root.serializeArgument(w, []const u8, "MATCH");
                        try root.serializeArgument(w, []const u8, p);
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

            pub fn serialize(
                self: Count,
                comptime root: type,
                w: *Writer,
            ) !void {
                switch (self) {
                    .NoCount => {},
                    .Count => |c| {
                        try root.serializeArgument(w, []const u8, "COUNT");
                        try root.serializeArgument(w, usize, c);
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
        pub fn serialize(
            self: SSCAN,
            comptime root: type,
            w: *Writer,
        ) !void {
            return root.serializeCommand(w, .{
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
    var correctMsg: Writer = .fixed(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg: Writer = .fixed(testBuf[0..]);

    {
        {
            correctMsg.end = 0;
            testMsg.end = 0;

            try serializer.serializeCommand(
                &testMsg,
                SSCAN.init("myset", "0", .NoPattern, .NoCount),
            );
            try serializer.serializeCommand(
                &correctMsg,
                .{ "SSCAN", "myset", "0" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.buffered(), testMsg.buffered() });
            try std.testing.expectEqualSlices(u8, correctMsg.buffered(), testMsg.buffered());
        }

        {
            correctMsg.end = 0;
            testMsg.end = 0;

            try serializer.serializeCommand(
                &testMsg,
                SSCAN.init("myset", "0", SSCAN.Pattern{ .Pattern = "zig_*" }, SSCAN.Count{ .Count = 5 }),
            );
            try serializer.serializeCommand(
                &correctMsg,
                .{ "SSCAN", "myset", 0, "MATCH", "zig_*", "COUNT", 5 },
            );

            // std.debug.warn("\n{}\n\n\n{}\n", .{ correctMsg.buffered(), testMsg.buffered() });
            try std.testing.expectEqualSlices(
                u8,
                correctMsg.buffered(),
                testMsg.buffered(),
            );
        }
    }
}
