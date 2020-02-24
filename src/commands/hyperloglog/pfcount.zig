// PFCOUNT key [key ...]

pub const PFCOUNT = struct {
    keys: []const u8,

    /// Instantiates a new PFCOUNT command.
    pub fn init(keys: []const []const u8) PFCOUNT {
        return .{ .keys = keys };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: PFCOUNT) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: PFCOUNT, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "PFCOUNT", self.keys });
        }
    };
};
