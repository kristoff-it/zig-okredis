// GEOPOS key member [member ...]

pub const GEOPOS = struct {
    key: []const u8,
    members: []const []const u8,

    /// Instantiates a new GEOPOS command.
    pub fn init(key: []const u8, members: []const []const u8) GEOPOS {
        return .{ .key = key, .members = members };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: GEOPOS) !void {
        if (self.members.len == 0) return error.MembersArrayIsEmpty;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: GEOPOS, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "GEOPOS", self.key, self.members });
        }
    };
};

test "basic usage" {
    const cmd = GEOPOS.init("mykey", &[_][]const u8{ "member1", "member2" });
    try cmd.validate();
}
