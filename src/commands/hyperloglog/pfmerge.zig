// PFMERGE destkey sourcekey [sourcekey ...]

pub const PFMERGE = struct {
    destkey: []const u8,
    sourcekeys: []const []const u8,

    /// Instantiates a new PFMERGE command.
    pub fn init(destkey: []const u8, sourcekeys: []const []const u8) PFMERGE {
        return .{ .destkey = destkey, .sourcekeys = sourcekeys };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(_: PFMERGE) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: PFMERGE, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "PFMERGE", self.destkey, self.sourcekeys });
        }
    };
};

test "basic usage" {
    const cmd = PFMERGE.init("finalcounter", &[_][]const u8{ "counter1", "counter2", "counter3" });
    try cmd.validate();
}
