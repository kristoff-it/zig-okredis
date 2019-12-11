// BITCOUNT key [start end]

pub const BITCOUNT = struct {
    key: []const u8,
    bounds: Bounds = .FullString,

    pub fn init(key: []const u8, bounds: Bounds) BITCOUNT {
        return .{ .key = key, .bounds = bounds };
    }

    pub fn validate(self: Self) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: BITCOUNT, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "BITCOUNT", self.key, self.bounds });
        }
    };

    pub const Bounds = union(enum) {
        FullString,
        Slice: struct {
            start: isize,
            end: isize,
        },

        pub const RedisArguments = struct {
            pub fn count(self: Bounds) usize {
                return switch (self) {
                    .FullString => 0,
                    .Slice => 2,
                };
            }

            pub fn serialize(self: Bounds, comptime rootSerializer: type, msg: var) !void {
                switch (self) {
                    .FullString => {},
                    .Slice => |slice| {
                        try rootSerializer.serializeArgument(msg, isize, slice.start);
                        try rootSerializer.serializeArgument(msg, isize, slice.end);
                    },
                }
            }
        };
    };
};

test "example" {
    const cmd = BITCOUNT.init("test", BITCOUNT.Bounds{ .Slice = .{ .start = -2, .end = -1 } });
}
