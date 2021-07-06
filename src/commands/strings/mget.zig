// MGET key [key ...]

pub const MGET = struct {
    keys: []const []const u8,

    pub fn init(keys: []const []const u8) MGET {
        return .{
            .keys = keys,
        };
    }

    pub fn validate(self: MGET) !void {
        if (self.keys.len == 0) return error.KeysArrayIsEmpty;
        for (self.keys) |k| {
            if (k.len == 0) return error.EmptyKeyName;
        }
    }

    const RedisCommand = struct {
        pub fn serialize(self: MGET, rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serialize(msg, .{ "MGET", self.keys });
        }
    };
};

test "basic usage" {
    _ = MGET.init(&[_][]const u8{ "lol", "key1", "key2" });
}
