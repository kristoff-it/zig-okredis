// INCRBY key increment
pub const INCRBY = struct {
    key: []const u8,
    increment: i64,

    pub fn init(key: []const u8, increment: i64) INCRBY {
        return .{ .key = key, .increment = increment };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: INCRBY, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "INCRBY", self.key, self.increment });
        }
    };
};

test "basic usage" {
    const cmd = INCRBY.init("lol", 42);
}
