pub const WATCH = struct {
    keys: []const []const u8,

    pub fn init(keys: []const []const u8) WATCH {
        return .{
            .keys = keys,
        };
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: WATCH, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "WATCH", self.keys });
        }
    };
};

pub const UNWATCH = struct {
    pub const RedisCommand = struct {
        pub fn serialize(self: UNWATCH, comptime rootSerializer: type, msg: anytype) !void {
            _ = self;
            return rootSerializer.serializeCommand(msg, .{"UNWATCH"});
        }
    };
};

pub const MULTI = struct {
    pub const RedisCommand = struct {
        pub fn serialize(self: MULTI, comptime rootSerializer: type, msg: anytype) !void {
            _ = self;
            return rootSerializer.serializeCommand(msg, .{"MULTI"});
        }
    };
};

pub const EXEC = struct {
    pub const RedisCommand = struct {
        pub fn serialize(self: EXEC, comptime rootSerializer: type, msg: anytype) !void {
            _ = self;
            return rootSerializer.serializeCommand(msg, .{"EXEC"});
        }
    };
};

pub const DISCARD = struct {
    pub const RedisCommand = struct {
        pub fn serialize(self: DISCARD, comptime rootSerializer: type, msg: anytype) !void {
            _ = self;
            return rootSerializer.serializeCommand(msg, .{"DISCARD"});
        }
    };
};
