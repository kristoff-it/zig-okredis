// DECRBY key decrement

pub const DECRBY = struct {
    key: []const u8,
    decrement: i64,

    const Self = @This();

    pub fn init(key: []const u8, decrement: i64) DECRBY {
        return .{ .key = key, .decrement = decrement };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: DECRBY, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "DECRBY", self.key, self.decrement });
        }
    };
};

test "basic usage" {
    _ = DECRBY.init("lol", 42);
}
