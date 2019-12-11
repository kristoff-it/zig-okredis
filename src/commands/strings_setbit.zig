// SETBIT key offset value
const Value = @import("./utils/common.zig").Value;

pub const SETBIT = struct {
    key: []const u8,
    offset: usize,
    value: Value,

    pub fn init(key: []const u8, offset: usize, value: var) SETBIT {
        return .{ .key = key, .offset = offset, .value = Value.fromVar(value) };
    }

    pub fn validate(self: SETBIT) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: SETBIT, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "SETBIT", self.key, self.offset, self.value });
        }
    };
};

test "basic usage" {
    const cmd = SETBIT.init("lol", 100, "banana");
}
