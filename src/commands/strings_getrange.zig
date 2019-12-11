// GETRANGE key start end

pub const GETRANGE = struct {
    key: []const u8,
    start: isize,
    end: isize,

    pub fn init(key: []const u8, start: isize, end: isize) GETRANGE {
        return .{ .key = key, .start = start, .end = end };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: GETRANGE, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "GETRANGE", self.key, self.start, self.end });
        }
    };
};

test "basic usage" {
    const cmd = GETRANGE.init("lol", 5, 100);
}
