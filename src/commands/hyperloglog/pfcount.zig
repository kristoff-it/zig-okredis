// PFCOUNT key [key ...]

pub const PFCOUNT = struct {
    keys: []const []const u8,

    /// Instantiates a new PFCOUNT command.
    pub fn init(keys: []const []const u8) PFCOUNT {
        return .{ .keys = keys };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: PFCOUNT) !void {
        if (self.keys.len == 0) {
            return error.EmptyKeySLice;
        }
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: PFCOUNT, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "PFCOUNT", self.keys });
        }
    };
};

test "basic usage" {
    const cmd = PFCOUNT.init(&[_][]const u8{ "counter1", "counter2", "counter3" });
    try cmd.validate();
}
