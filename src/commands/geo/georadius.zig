// GEORADIUS key longitude latitude radius m|km|ft|mi [WITHCOORD] [WITHDIST] [WITHHASH] [COUNT count] [ASC|DESC] [STORE key] [STOREDIST key]

const Unit = @import("./_utils.zig").Unit;

pub const GEORADIUS = struct {
    key: []const u8,
    longitude: f64,
    latitude: f64,
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
        longitude: f64,
        latitude: f64,
        radius: f64,
        unit: Unit,
        withcoord: bool,
        withdist: bool,
        withhash: bool,
        count: ?u64,
        ordering: ?Ordering,
        store: ?[]const u8,
        storedist: ?[]const u8,
    ) GEORADIUS {
        return .{
            .key = key,
            .longitude = longitude,
            .latitude = latitude,
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

    pub fn validate(_: GEORADIUS) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: GEORADIUS, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{
                "GEORADIUS",
                self.key,
                self.longitude,
                self.latitude,
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
        pub fn count(self: GEORADIUS) usize {
            var total = 0;
            if (self.count) |_| total += 2;
            if (self.ordering) |_| total += 1;
            if (self.store) |_| total += 2;
            if (self.storedist) |_| total += 2;
            return total;
        }

        pub fn serialize(self: GEORADIUS, comptime rootSerializer: type, msg: anytype) !void {
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
    const cmd = GEORADIUS.init("mykey", 0.1, 0.2, 20, .meters, true, true, true, 10, null, null, null);
    try cmd.validate();
}
