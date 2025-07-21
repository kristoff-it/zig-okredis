// HINCRBY key field increment

const std = @import("std");
const Writer = std.Io.Writer;

pub const HINCRBY = struct {
    key: []const u8,
    field: []const u8,
    increment: i64,

    pub fn init(key: []const u8, field: []const u8, increment: i64) HINCRBY {
        return .{ .key = key, .field = field, .increment = increment };
    }

    pub fn validate(_: HINCRBY) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(
            self: HINCRBY,
            comptime rootSerializer: type,
            w: *Writer,
        ) !void {
            return rootSerializer.serializeCommand(w, .{
                "HINCRBY",
                self.key,
                self.field,
                self.increment,
            });
        }
    };
};

test "basic usage" {
    _ = HINCRBY.init("hashname", "fieldname", 42);
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
            HINCRBY.init("mykey", "myfield", 42),
        );
        try serializer.serializeCommand(
            &correctMsg,
            .{ "HINCRBY", "mykey", "myfield", 42 },
        );

        try std.testing.expectEqualSlices(
            u8,
            correctMsg.buffered(),
            testMsg.buffered(),
        );
    }
}
