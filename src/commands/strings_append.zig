// APPEND key value
pub const APPEND = struct {
    key: []const u8,
    value: []const u8,

    pub fn init(key: []const u8, value: []const u8) APPEND {
        return .{ .key = key, .value = value };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
        if (self.value.len == 0) return error.EmptyValue;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: APPEND, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "APPEND", self.key, self.value });
        }
    };
};

test "example" {
    const cmd = APPEND.init("noun", "ism");
}
