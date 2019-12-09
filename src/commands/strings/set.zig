// SET key value [EX seconds|PX milliseconds] [NX|XX]

pub const SET = struct {
    key: []const u8,
    value: Value,
    expire: Expire,
    existing: Existing,

    const Self = @This();
    pub fn init(key: []const u8, value: var, expire: Expire, existing: Existing) Self {
        const wrappedVal = switch (@typeInfo(@typeOf(value))) {
            .Int, .ComptimeInt => Value{ .Int = value },
            .Float, .ComptimeFloat => Value{ .Float = value },
            .Array => Value{ .String = value[0..] },
            .Pointer => Value{ .String = value },
            else => @compileError("Unsupported type."),
        };

        return .{
            .key = key,
            .value = wrappedVal,
            .expire = expire,
            .existing = existing,
        };
    }

    pub const Redis = struct {
        pub const Command = struct {
            pub fn serialize(self: Self, comptime rootSerializer: type, msg: var) !void {
                return rootSerializer.serializeCommand(msg, .{
                    "SET",
                    self.key,
                    self.value,
                    self.expire,
                    self.existing,
                });
            }
        };
    };
};

const Value = union(enum) {
    String: []const u8,
    Int: i64,
    Float: f64,
    pub const Redis = struct {
        pub const Arguments = struct {
            pub fn count(self: Value) usize {
                return 1;
            }

            pub fn serialize(self: Value, comptime rootSerializer: type, msg: var) !void {
                switch (self) {
                    .String => |s| try rootSerializer.serializeArgument(msg, []const u8, s),
                    .Int => |i| try rootSerializer.serializeArgument(msg, i64, i),
                    .Float => |f| try rootSerializer.serializeArgument(msg, f64, f),
                }
            }
        };
    };
};

pub const Expire = union(enum) {
    NoExpire,
    Seconds: u64,
    Milliseconds: u64,
    pub const Redis = struct {
        pub const Arguments = struct {
            pub fn count(self: Expire) usize {
                return switch (self) {
                    .NoExpire => 0,
                    else => 2,
                };
            }

            pub fn serialize(self: Expire, comptime rootSerializer: type, msg: var) !void {
                switch (self) {
                    .NoExpire => {},
                    .Seconds => |s| {
                        try rootSerializer.serializeArgument(msg, []const u8, "EX");
                        try rootSerializer.serializeArgument(msg, u64, s);
                    },
                    .Milliseconds => |m| {
                        try rootSerializer.serializeArgument(msg, []const u8, "PX");
                        try rootSerializer.serializeArgument(msg, u64, m);
                    },
                }
            }
        };
    };
};

const Existing = union(enum) {
    Always,
    IfNotExisting,
    IfAlreadyExisting,
    const ArgSelf = @This();
    pub const Redis = struct {
        pub const Arguments = struct {
            pub fn count(self: Existing) usize {
                return switch (self) {
                    .Always => 0,
                    else => 1,
                };
            }

            pub fn serialize(self: Existing, comptime rootSerializer: type, msg: var) !void {
                switch (self) {
                    .Always => {},
                    .IfNotExisting => |s| try rootSerializer.serializeArgument(msg, []const u8, "NX"),
                    .IfAlreadyExisting => |m| try rootSerializer.serializeArgument(msg, []const u8, "XX"),
                }
            }
        };
    };
};

test "basic usage" {
    var cmd = SET.init("mykey", 42, .NoExpire, .Always);
    cmd = SET.init("mykey", "banana", .NoExpire, .Always);
    // cmd = SET.init("mykey", "banana", .{ .Seconds = 40 }, .IfNotExisting);
}
