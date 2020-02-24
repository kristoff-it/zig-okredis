// GET key
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
        pub fn serialize(self: GET, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "GET", self.key });
        }
    };
};

test "example" {
    const cmd = GET.init("lol");
    try cmd.validate();
}

test "serializer" {
    const std = @import("std");
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.SliceOutStream.init(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.SliceOutStream.init(testBuf[0..]);
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            GET.init("mykey"),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "GET", "mykey" },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
