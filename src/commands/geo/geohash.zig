// GEOHASH key member [member ...]

pub const GEOHASH = struct {
    key: []const u8,
    members: []const []const u8,

    /// Instantiates a new GEOHASH command.
    pub fn init(key: []const u8, members: []const []const u8) GEOHASH {
        return .{ .key = key, .members = members };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: GEOHASH) !void {
        if (self.members.len == 0) return error.MembersArrayIsEmpty;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: GEOHASH, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "GEOHASH", self.key, self.members });
        }
    };
};

test "basic usage" {
    const cmd = GEOHASH.init("mykey", &[_][]const u8{ "member1", "member2" });
    try cmd.validate();
}
