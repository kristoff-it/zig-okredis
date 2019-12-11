// BITOP operation destkey key [key ...]

// TODO: implement Op as a Redis.Arguments?

pub const BITOP = struct {
    operation: Op,
    destKey: []const u8,
    sourceKeys: []const []const u8,

    pub fn init(operation: Op, destKey: []const u8, sourceKeys: []const []const u8) BITOP {
        return .{ .operation = operation, .destKey = destKey, .sourceKeys = sourceKeys };
    }

    pub fn validate(self: BITOP) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
        if (self.value.len == 0) return error.EmptyValue;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: BITOP, comptime rootSerializer: type, msg: var) !void {
            const op = switch (self.operation) {
                .AND => "AND",
                .OR => "OR",
                .XOR => "XOR",
                .NOT => "NOT",
            };
            return rootSerializer.serializeCommand(msg, .{ "BITOP", op, self.destKey, self.sourceKeys });
        }
    };

    pub const Op = enum {
        AND,
        OR,
        XOR,
        NOT,
    };
};

test "basic usage" {
    const cmd = BITOP.init(.AND, "result", &[_][]const u8{ "key1", "key2" });
}
