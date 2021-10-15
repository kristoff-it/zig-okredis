// DECR key

pub const DECR = struct {
    key: []const u8,

    const Self = @This();

    pub fn init(key: []const u8) DECR {
        return .{ .key = key };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: DECR, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "DECR", self.key });
        }
    };
};

test "basic usage" {
    _ = DECR.init("lol");
}
