// INCRBYFLOAT key increment
pub const INCRBYFLOAT = struct {
    key: []const u8,
    increment: f64,

    pub fn init(key: []const u8, increment: f64) INCRBYFLOAT {
        return .{ .key = key, .increment = increment };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: INCRBYFLOAT, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "INCRBYFLOAT", self.key, self.increment });
        }
    };
};

test "basic usage" {
    const cmd = INCRBYFLOAT.init("lol", 42);
}
