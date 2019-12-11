// INCR key

pub const INCR = struct {
    key: []const u8,

    pub fn init(key: []const u8) INCR {
        return .{ .key = key };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: INCR, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "INCR", self.key });
        }
    };
};

test "example" {
    const cmd = INCR.init("lol");
}
