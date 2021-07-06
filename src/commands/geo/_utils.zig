pub const Unit = enum {
    meters,
    kilometers,
    feet,
    miles,

    pub const RedisArguments = struct {
        pub fn count(_: Unit) usize {
            return 1;
        }

        pub fn serialize(self: Unit, comptime rootSerializer: type, msg: anytype) !void {
            const symbol = switch (self) {
                .meters => "m",
                .kilometers => "km",
                .feet => "ft",
                .miles => "mi",
            };

            try rootSerializer.serializeArgument(msg, []const u8, symbol);
        }
    };
};
