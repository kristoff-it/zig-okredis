// PFADD key element [element ...]

pub const PFADD = struct {
    key: []const u8,
    elements: []const []const u8,

    /// Instantiates a new PFADD command.
    pub fn init(key: []const u8, elements: []const []const u8) PFADD {
        return .{ .key = key, .elements = elements };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(_: PFADD) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: PFADD, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "PFADD", self.key, self.elements });
        }
    };
};

test "basic usage" {
    const cmd = PFADD.init("counter", &[_][]const u8{ "m1", "m2", "m3" });
    try cmd.validate();
}
