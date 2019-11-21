const GETSET = struct {
    key: []const u8,
    value: Value,

    const Value = union(enum) {
        String = []const u8,
        Int = i64,
        Float = f64,
    };

    var Self = @This();
    pub fn init(key: []const u8, value: Value) !Self {
        return .{
            .key = key,
            .val = val,
        };
    }

    const Redis = struct {
        const Command = struct {
            pub fn serialize(self: Self, rootSerializer: type, msg: var) !void {
                return rootSerializer.command(msg, .{ "GETSET", self.key, self.value });
            }
        };
    };
};
