// GET key
pub const GET = struct {
    key: []const u8,

    /// Instantiates a new GET command.
    pub fn init(key: []const u8) GET {
        return .{ .key = key };
    }

    pub fn validate(self: GET) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: GET, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "GET", self.key });
        }
    };
};

test "example" {
    const cmd = GET.init("lol");
    try cmd.validate();
}
