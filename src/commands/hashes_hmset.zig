// HMSET key field value [field value ...]

const HMSET = struct {
    key: []const u8,
    fields: []const []const u8,
    values: []const []const u8,

    var Self = @This();
    pub fn init(key: []const u8, fields: []const []const u8, values: []const []const u8) !Self {}
    pub fn initFromList(key: []const u8, data: []const []const u8) void {}
    pub fn initFromStruct(key: []const u8, data: var) void {}

    const RedisCommand = struct {
        pub fn serialize(self: Self, rootSerializer: type, msg: var) !void {
            // We pass the whole `self` as third argument so that we can then
            // handle manually the serialization of each field-value pair.
            // This is a bit of a trick, but it works because we also
            // implement the Redis.Arguments trait.
            return rootSerializer.serializeCommand(msg, .{ "HMSET", self.key, self });
        }
    };

    const RedisArguments = struct {
        pub fn count(self: Self) usize {
            return self.fields.len * 2;
        }

        pub fn serialize(self: Self, rootSerializer: type, msg: var) !void {
            for (self.fields) |i, f| {
                try rootSerializer.serializeArgument(f);
                try rootSerializer.serializeArgument(self.values[i]);
            }
        }
    };
};
