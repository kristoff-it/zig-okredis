const std = @import("std");
const serializer = @import("./serializer.zig").CommandSerializer;

pub const SET = @import("./commands/strings/set.zig").SET;

test "SET" {
    const Expire = @import("./commands/strings/set.zig").Expire;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.SliceOutStream.init(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.SliceOutStream.init(testBuf[0..]);

    {
        try serializer.serializeCommand(
            &testMsg.stream,
            SET.init("mykey", 42, .NoExpire, .Always),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "SET", "mykey", "42" },
        );

        std.testing.expectEqualSlices(u8, testMsg.getWritten(), correctMsg.getWritten());
    }

    {
        try serializer.serializeCommand(
            &testMsg.stream,
            SET.init("mykey", "banana", .NoExpire, .IfNotExisting),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "SET", "mykey", "banana", "NX" },
        );

        std.testing.expectEqualSlices(u8, testMsg.getWritten(), correctMsg.getWritten());
    }

    {
        try serializer.serializeCommand(
            &testMsg.stream,
            SET.init("mykey", "banana", Expire{ .Seconds = 20 }, .IfAlreadyExisting),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "SET", "mykey", "banana", "EX", "20", "XX" },
        );

        std.testing.expectEqualSlices(u8, testMsg.getWritten(), correctMsg.getWritten());
    }
}
