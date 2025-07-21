// GET key

const std = @import("std");
const Writer = std.Io.Writer;

pub const GET = struct {
    key: []const u8,

    /// Instantiates a new GET command.
    pub fn init(key: []const u8) GET {
        return .{ .key = key };
    }

    pub fn validate(self: GET) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: GET, comptime root: type, w: *Writer) !void {
            return root.serializeCommand(w, .{ "GET", self.key });
        }
    };
};

test "example" {
    const cmd = GET.init("lol");
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
            GET.init("mykey"),
        );
        try serializer.serializeCommand(
            &correctMsg,
            .{ "GET", "mykey" },
        );

        try std.testing.expectEqualSlices(
            u8,
            correctMsg.buffered(),
            testMsg.buffered(),
        );
    }
}
