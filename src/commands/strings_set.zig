const Value = @import("./utils/common.zig").Value;

/// SET key value [EX seconds|PX milliseconds] [NX|XX]
pub const SET = struct {
    key: []const u8,

    /// Users should provide either a string or a number to `.init()`.
    value: Value,

    /// Time To Live (TTL) for the key, defaults to `.NoExpire`.
    expire: Expire = .NoExpire,

    /// Execution constraints, defaults to `.NoCondition` (executes the command unconditionally).
    conditions: Conditions = .NoConditions,

    /// Provide either a number or a string as `value`.
    pub fn init(key: []const u8, value: var, expire: Expire, conditions: Conditions) SET {
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
        pub fn serialize(self: SET, comptime rootSerializer: type, msg: var) !void {
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

            pub fn serialize(self: Expire, comptime rootSerializer: type, msg: var) !void {
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

            pub fn serialize(self: Conditions, comptime rootSerializer: type, msg: var) !void {
                switch (self) {
                    .NoConditions => {},
                    .IfNotExisting => |s| try rootSerializer.serializeArgument(msg, []const u8, "NX"),
                    .IfAlreadyExisting => |m| try rootSerializer.serializeArgument(msg, []const u8, "XX"),
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
