const Value = @import("../_common_utils.zig").Value;

// GETSET key value
// TODO: check if this is correct
pub const GETSET = struct {
    //! ```
    //! const cmd1 = GETSET.init("lol", 42);
    //! const cmd2 = GETSET.init("lol", "banana");
    //! ```
    key: []const u8,
    value: Value,

    const Self = @This();

    pub fn init(key: []const u8, value: anytype) GETSET {
        return .{
            .key = key,
            .value = Value.fromVar(value),
        };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    const Redis = struct {
        const Command = struct {
            pub fn serialize(self: GETSET, rootSerializer: type, msg: anytype) !void {
                return rootSerializer.command(msg, .{ "GETSET", self.key, self.value });
            }
        };
    };
};

test "example" {
    _ = GETSET.init("lol", "banana");
}
