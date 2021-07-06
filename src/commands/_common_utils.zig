pub const FV = struct {
    field: []const u8,
    value: []const u8,

    pub const RedisArguments = struct {
        pub fn count(_: FV) usize {
            return 2;
        }

        pub fn serialize(self: FV, comptime rootSerializer: type, msg: anytype) !void {
            try rootSerializer.serializeArgument(msg, []const u8, self.field);
            try rootSerializer.serializeArgument(msg, []const u8, self.value);
        }
    };
};

/// Union used to allow users to pass numbers transparently to SET-like commands.
pub const Value = union(enum) {
    String: []const u8,
    Int: i64,
    Float: f64,

    /// Wraps either a string or a number.
    pub fn fromVar(value: anytype) Value {
        return switch (@typeInfo(@TypeOf(value))) {
            .Int, .ComptimeInt => Value{ .Int = value },
            .Float, .ComptimeFloat => Value{ .Float = value },
            .Array => Value{ .String = value[0..] },
            .Pointer => Value{ .String = value },
            else => @compileError("Unsupported type."),
        };
    }

    pub const RedisArguments = struct {
        pub fn count(_: Value) usize {
            return 1;
        }

        pub fn serialize(self: Value, comptime rootSerializer: type, msg: anytype) !void {
            switch (self) {
                .String => |s| try rootSerializer.serializeArgument(msg, []const u8, s),
                .Int => |i| try rootSerializer.serializeArgument(msg, i64, i),
                .Float => |f| try rootSerializer.serializeArgument(msg, f64, f),
            }
        }
    };
};
