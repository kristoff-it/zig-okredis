// SUNION key [key ...]

const std = @import("std");
const Writer = std.Io.Writer;

pub const SUNION = struct {
    keys: []const []const u8,

    /// Instantiates a new SUNION command.
    pub fn init(keys: []const []const u8) SUNION {
        return .{ .keys = keys };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: SUNION) !void {
        if (self.keys.len == 0) return error.KeysArrayIsEmpty;
        // TODO: should we check for duplicated keys? if so, we need an allocator, methinks.
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: SUNION, comptime root: type, w: *Writer) !void {
            return root.serializeCommand(w, .{ "SUNION", self.keys });
        }
    };
};

test "basic usage" {
    const cmd = SUNION.init(&[_][]const u8{ "set1", "set2" });
    try cmd.validate();
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
                SUNION.init(&[_][]const u8{ "set1", "set2" }),
            );
            try serializer.serializeCommand(
                &correctMsg,
                .{ "SUNION", "set1", "set2" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(
                u8,
                correctMsg.buffered(),
                testMsg.buffered(),
            );
        }
    }
}
