const DEL = struct {
    keys: []const []const u8,

    const Self = @This();
    pub fn init(keys: []const []const u8) Self {
        return .{
            .keys = keys,
        };
    }

    const Redis = struct {
        const Command = struct {
            pub fn serialize(self: Self, rootSerializer: type, msg: var) !void {
                return rootSerializer.serialize(msg, .{ "DEL", self.keys });
            }
        };
    };
};

test "basic usage" {
    const cmd = DEL.init(.{ "lol", "123", "test" });
}
