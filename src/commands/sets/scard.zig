//  SCARD key

const std = @import("std");
const Writer = std.Io.Writer;

pub const SCARD = struct {
    key: []const u8,

    /// Instantiates a new SCARD command.
    pub fn init(key: []const u8) SCARD {
        return .{ .key = key };
    }

    pub fn validate(self: SCARD) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(
            self: SCARD,
            comptime root_serializer: type,
            w: *Writer,
        ) !void {
            return root_serializer.serializeCommand(w, .{ "SCARD", self.key });
        }
    };
};

test "example" {
    const cmd = SCARD.init("lol");
    try cmd.validate();
}

test "serializer" {
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg: Writer = .fixed(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg: Writer = .fixed(testBuf[0..]);
    {
        correctMsg.end = 0;
        testMsg.end = 0;

        try serializer.serializeCommand(
            &testMsg,
            SCARD.init("myset"),
        );
        try serializer.serializeCommand(
            &correctMsg,
            .{ "SCARD", "myset" },
        );

        try std.testing.expectEqualSlices(
            u8,
            correctMsg.buffered(),
            testMsg.buffered(),
        );
    }
}
