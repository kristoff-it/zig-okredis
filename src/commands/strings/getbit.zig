// GETBIT key offset

const std = @import("std");
const Writer = std.Io.Writer;

pub const GETBIT = struct {
    key: []const u8,
    offset: usize,

    const Self = @This();

    pub fn init(key: []const u8, offset: usize) GETBIT {
        return .{ .key = key, .offset = offset };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: GETBIT, comptime root: type, w: *Writer) !void {
            return root.serializeCommand(
                w,
                .{ "GETBIT", self.key, self.offset },
            );
        }
    };
};

test "basic usage" {
    _ = GETBIT.init("lol", 100);
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
            GETBIT.init("mykey", 100),
        );
        try serializer.serializeCommand(
            &correctMsg,
            .{ "GETBIT", "mykey", 100 },
        );

        try std.testing.expectEqualSlices(
            u8,
            correctMsg.buffered(),
            testMsg.buffered(),
        );
    }
}
