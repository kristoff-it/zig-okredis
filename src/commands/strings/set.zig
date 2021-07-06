const Value = @import("../_common_utils.zig").Value;

/// SET key value [EX seconds|PX milliseconds] [NX|XX]
pub const SET = struct {
    //! Command builder for SET.
    //!
    //! Allows you to use both strings and numbers as values.
    //! ```
    //! const cmd1 = SET.init("mykey", 42, .NoExpire, .NoConditions);
    //! const cmd2 = SET.init("mykey", "banana", .NoExpire, .IfNotExisting);
    //! ```

    key: []const u8,

    /// Users should provide either a string or a number to `.init()`.
    value: Value,

    /// Time To Live (TTL) for the key, defaults to `.NoExpire`.
    expire: Expire = .NoExpire,

    /// Execution constraints, defaults to `.NoCondition` (executes the command unconditionally).
    conditions: Conditions = .NoConditions,

    /// Provide either a number or a string as `value`.
    pub fn init(key: []const u8, value: anytype, expire: Expire, conditions: Conditions) SET {
        return .{
            .key = key,
            .value = Value.fromVar(value),
            .expire = expire,
            .conditions = conditions,
        };
    }

    pub fn validate(self: SET) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: SET, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{
                "SET",
                self.key,
                self.value,
                self.expire,
                self.conditions,
            });
        }
    };

    pub const Expire = union(enum) {
        NoExpire,
        Seconds: u64,
        Milliseconds: u64,

        pub const RedisArguments = struct {
            pub fn count(self: Expire) usize {
                return switch (self) {
                    .NoExpire => 0,
                    else => 2,
                };
            }

            pub fn serialize(self: Expire, comptime rootSerializer: type, msg: anytype) !void {
                switch (self) {
                    .NoExpire => {},
                    .Seconds => |s| {
                        try rootSerializer.serializeArgument(msg, []const u8, "EX");
                        try rootSerializer.serializeArgument(msg, u64, s);
                    },
                    .Milliseconds => |m| {
                        try rootSerializer.serializeArgument(msg, []const u8, "PX");
                        try rootSerializer.serializeArgument(msg, u64, m);
                    },
                }
            }
        };
    };

    pub const Conditions = union(enum) {
        /// Creates the key uncontidionally.
        NoConditions,

        /// Creates the key only if it does not exist yet.
        IfNotExisting,

        /// Only overrides an existing key.
        IfAlreadyExisting,

        pub const RedisArguments = struct {
            pub fn count(self: Conditions) usize {
                return switch (self) {
                    .NoConditions => 0,
                    else => 1,
                };
            }

            pub fn serialize(self: Conditions, comptime rootSerializer: type, msg: anytype) !void {
                switch (self) {
                    .NoConditions => {},
                    .IfNotExisting => try rootSerializer.serializeArgument(msg, []const u8, "NX"),
                    .IfAlreadyExisting => try rootSerializer.serializeArgument(msg, []const u8, "XX"),
                }
            }
        };
    };
};

test "basic usage" {
    var cmd = SET.init("mykey", 42, .NoExpire, .NoConditions);
    cmd = SET.init("mykey", "banana", .NoExpire, .IfNotExisting);
    try cmd.validate();
}

test "serializer" {
    const std = @import("std");
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.fixedBufferStream(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.fixedBufferStream(testBuf[0..]);

    {
        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                testMsg.writer(),
                SET.init("mykey", 42, .NoExpire, .NoConditions),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SET", "mykey", "42" },
            );

            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                testMsg.writer(),
                SET.init("mykey", "banana", .NoExpire, .IfNotExisting),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SET", "mykey", "banana", "NX" },
            );

            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                testMsg.writer(),
                SET.init("mykey", "banana", SET.Expire{ .Seconds = 20 }, .IfAlreadyExisting),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "SET", "mykey", "banana", "EX", "20", "XX" },
            );

            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
