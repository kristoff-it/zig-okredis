pub const GET = struct {
    key: []const u8,

    pub fn init(key: []const u8) GET {
        return .{ .key = key };
    }

    pub const Redis = struct {
        pub const Command = struct {
            pub fn serialize(self: GET, comptime rootSerializer: type, msg: var) !void {
                return rootSerializer.serializeCommand(msg, .{ "GET", self.key });
            }
        };
    };
};

test "basic usage" {
    const cmd = GET.init("lol");
}
