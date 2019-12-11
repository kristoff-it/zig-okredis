// GETBIT key offset

pub const GETBIT = struct {
    key: []const u8,
    offset: usize,

    pub fn init(key: []const u8, offset: usize) GETBIT {
        return .{ .key = key, .offset = offset };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: GETBIT, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "GETBIT", self.key, self.offset });
        }
    };
};

test "basic usage" {
    const cmd = GETBIT.init("lol", 100);
}
