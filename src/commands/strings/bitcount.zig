// BITCOUNT key [start end]

pub const BITCOUNT = struct {
    //! ```
    //! const cmd = BITCOUNT.init("test", BITCOUNT.Bounds{ .Slice = .{ .start = -2, .end = -1 } });
    //! ```

    key: []const u8,
    bounds: Bounds = .FullString,

    const Self = @This();

    pub fn init(key: []const u8, bounds: Bounds) BITCOUNT {
        return .{ .key = key, .bounds = bounds };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: BITCOUNT, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "BITCOUNT", self.key, self.bounds });
        }
    };

    pub const Bounds = union(enum) {
        FullString,
        Slice: struct {
            start: isize,
            end: isize,
        },

        pub const RedisArguments = struct {
            pub fn count(self: Bounds) usize {
                return switch (self) {
                    .FullString => 0,
                    .Slice => 2,
                };
            }

            pub fn serialize(self: Bounds, comptime rootSerializer: type, msg: anytype) !void {
                switch (self) {
                    .FullString => {},
                    .Slice => |slice| {
                        try rootSerializer.serializeArgument(msg, isize, slice.start);
                        try rootSerializer.serializeArgument(msg, isize, slice.end);
                    },
                }
            }
        };
    };
};

test "example" {
    _ = BITCOUNT.init("test", BITCOUNT.Bounds{ .Slice = .{ .start = -2, .end = -1 } });
}

test "serializer" {
    const std = @import("std");
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.fixedBufferStream(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.fixedBufferStream(testBuf[0..]);

    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            testMsg.writer(),
            BITCOUNT.init("mykey", BITCOUNT.Bounds{ .Slice = .{ .start = 1, .end = 10 } }),
        );
        try serializer.serializeCommand(
            correctMsg.writer(),
            .{ "BITCOUNT", "mykey", 1, 10 },
        );

        try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
