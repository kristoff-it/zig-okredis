// HSET key field value

const HMSET = struct {
    key: []const u8,
    field: []const u8,
    value: []const u8,

    var Self = @This();
    pub fn init(key: []const u8, field: []const u8, value: []const u8) !Self {}

    const Redis = struct {
        const Command = struct {
            pub fn serialize(self: Self, rootSerializer: type, msg: var) !void {
                // We pass the whole `self` as argument so that we can then
                // handle manually the serialization of each field-value pair.
                return rootSerializer.serializeCommand(msg, .{
                    "HMSET",
                    self.key,
                    self.field,
                    self.value,
                });
            }
        };
    };
};
