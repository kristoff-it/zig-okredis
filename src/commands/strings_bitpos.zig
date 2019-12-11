// BITPOS key bit [start] [end]

pub const Bit = enum {
    Zero,
    One,
};

pub const BITPOS = struct {
    key: []const u8,
    bit: Bit,
    bounds: Bounds,

    pub fn init(key: []const u8, bit: Bit, start: ?isize, end: ?isize) BITPOS {
        return .{
            .key = key,
            .bit = bit,
            .bounds = Bounds{ .start = start, .end = end },
        };
    }

    pub fn validate(self: BITPOS) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: BITPOS, comptime rootSerializer: type, msg: var) !void {
            const bit = switch (self.bit) {
                .Zero => "0",
                .One => "1",
            };
            return rootSerializer.serializeCommand(msg, .{ "BITPOS", self.key, bit, self.bounds });
        }
    };
};

const Bounds = struct {
    start: ?isize,
    end: ?isize,

    pub const RedisArguments = struct {
        pub fn count(self: Bounds) usize {
            const one: usize = 1;
            const zero: usize = 0;
            return (if (self.start) |_| one else zero) + (if (self.end) |_| one else zero);
        }

        pub fn serialize(self: Bounds, comptime rootSerializer: type, msg: var) !void {
            if (self.start) |s| {
                try rootSerializer.serializeArgument(msg, isize, s);
            }
            if (self.end) |e| {
                try rootSerializer.serializeArgument(msg, isize, e);
            }
        }
    };
};

test "basic usage" {
    const cmd = BITPOS.init("test", .Zero, -3, null);
}
