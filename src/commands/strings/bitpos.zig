// BITPOS key bit [start] [end]

pub const Bit = enum {
    Zero,
    One,
};

pub const BITPOS = struct {
    //! ```
    //! const cmd = BITPOS.init("test", .Zero, -3, null);
    //! ```

    key: []const u8,
    bit: Bit,
    bounds: Bounds,

    pub fn init(key: []const u8, bit: Bit, start: ?isize, end: ?isize) BITPOS {
        return .{
            .key = key,
            .bit = bit,
            .bounds = Bounds{ .start = start, .end = end },
        };
    }

    pub fn validate(self: BITPOS) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: BITPOS, comptime rootSerializer: type, msg: anytype) !void {
            const bit = switch (self.bit) {
                .Zero => "0",
                .One => "1",
            };
            return rootSerializer.serializeCommand(msg, .{ "BITPOS", self.key, bit, self.bounds });
        }
    };
};

const Bounds = struct {
    start: ?isize,
    end: ?isize,

    pub const RedisArguments = struct {
        pub fn count(self: Bounds) usize {
            const one: usize = 1;
            const zero: usize = 0;
            return (if (self.start) |_| one else zero) + (if (self.end) |_| one else zero);
        }

        pub fn serialize(self: Bounds, comptime rootSerializer: type, msg: anytype) !void {
            if (self.start) |s| {
                try rootSerializer.serializeArgument(msg, isize, s);
            }
            if (self.end) |e| {
                try rootSerializer.serializeArgument(msg, isize, e);
            }
        }
    };
};

test "basic usage" {
    _ = BITPOS.init("test", .Zero, -3, null);
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

        var cmd = BITPOS.init("test", .Zero, -3, null);
        try serializer.serializeCommand(
            testMsg.writer(),
            cmd,
        );
        try serializer.serializeCommand(
            correctMsg.writer(),
            .{ "BITPOS", "test", "0", "-3" },
        );

        try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}
