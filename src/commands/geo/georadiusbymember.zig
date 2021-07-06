// GEORADIUSBYMEMBER key member radius m|km|ft|mi [WITHCOORD] [WITHDIST] [WITHHASH] [COUNT count] [ASC|DESC] [STORE key] [STOREDIST key]

const Unit = @import("./_utils.zig").Unit;

pub const GEORADIUSBYMEMBER = struct {
    key: []const u8,
    member: []const u8,
    radius: f64,
    unit: Unit,
    withcoord: bool,
    withdist: bool,
    withhash: bool,

    count: ?u64,
    ordering: ?Ordering,
    store: ?[]const u8,
    storedist: ?[]const u8,

    pub const Ordering = enum {
        Asc,
        Desc,
    };

    pub fn init(
        key: []const u8,
        member: []const u8,
        radius: f64,
        unit: Unit,
        withcoord: bool,
        withdist: bool,
        withhash: bool,
        count: ?u64,
        ordering: ?Ordering,
        store: ?[]const u8,
        storedist: ?[]const u8,
    ) GEORADIUSBYMEMBER {
        return .{
            .key = key,
            .member = member,
            .radius = radius,
            .unit = unit,
            .withcoord = withcoord,
            .withdist = withdist,
            .withhash = withhash,
            .count = count,
            .ordering = ordering,
            .store = store,
            .storedist = storedist,
        };
    }

    pub fn validate(_: GEORADIUSBYMEMBER) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: GEORADIUSBYMEMBER, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{
                "GEORADIUSBYMEMBER",
                self.key,
                self.member,
                self.radius,
                self.unit,
                self.withcoord,
                self.withdist,
                self.withhash,
                self,
            });
        }
    };

    pub const RedisArguments = struct {
        pub fn count(self: GEORADIUSBYMEMBER) usize {
            var total = 0;
            if (self.count) |_| total += 2;
            if (self.ordering) |_| total += 1;
            if (self.store) |_| total += 2;
            if (self.storedist) |_| total += 2;
            return total;
        }

        pub fn serialize(self: GEORADIUSBYMEMBER, comptime rootSerializer: type, msg: anytype) !void {
            if (self.count) |c| {
                try rootSerializer.serializeArgument(msg, []const u8, "COUNT");
                try rootSerializer.serializeArgument(msg, u64, c);
            }

            if (self.ordering) |o| {
                const ord = switch (o) {
                    .Asc => "ASC",
                    .Desc => "DESC",
                };
                try rootSerializer.serializeArgument(msg, []const u8, ord);
            }

            if (self.store) |s| {
                try rootSerializer.serializeArgument(msg, []const u8, "STORE");
                try rootSerializer.serializeArgument(msg, []const u8, s);
            }

            if (self.storedist) |sd| {
                try rootSerializer.serializeArgument(msg, []const u8, "STOREDIST");
                try rootSerializer.serializeArgument(msg, []const u8, sd);
            }
        }
    };
};

test "basic usage" {
    const cmd = GEORADIUSBYMEMBER.init("mykey", "mymember", 20, .meters, false, false, false, 0, .Asc, null, null);
    try cmd.validate();
}
