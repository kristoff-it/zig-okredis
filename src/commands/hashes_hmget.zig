// HMGET key field [field ...]

const std = @import("std");
const common = @import("./utils/common.zig");
const FV = common.FV;

pub const HMGET = struct {
    key: []const u8,
    fields: []const []const u8,

    /// Instantiates a new HMGET command.
    pub fn init(key: []const u8, fields: []const []const u8) HMGET {
        return .{ .key = key, .fields = fields };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: HMGET) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
        if (self.fields.len == 0) return error.FieldsArrayIsEmpty;

        // TODO: how the hell do I check for dups without an allocator?
        var i: usize = 0;
        while (i < self.fields.len) : (i += 1) {
            if (self.fields[i].len == 0) return error.EmptyFieldName;
        }
    }

    // This reassignment is necessary to avoid having two definitions of
    // RedisCommand in the same scope (it causes a shadowing error).
    pub const forStruct = _forStruct;

    pub const RedisCommand = struct {
        pub fn serialize(self: HMGET, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{ "HMGET", self.key, self.fields });
        }
    };
};

fn _forStruct(comptime T: type) type {
    // TODO: there is some duplicated code with xread. Values should be a dedicated generic type.
    if (@typeId(T) != .Struct) @compileError("Only Struct types allowed.");
    return struct {
        key: []const u8,

        const Self = @This();
        pub fn init(key: []const u8) Self {
            return .{ .key = key };
        }

        /// Validates if the command is syntactically correct.
        pub fn validate(self: Self) !void {
            if (self.key.len == 0) return error.EmptyKeyName;
        }

        pub const RedisCommand = struct {
            pub fn serialize(self: Self, comptime rootSerializer: type, msg: var) !void {
                return rootSerializer.serializeCommand(msg, .{
                    "HMGET",
                    self.key,

                    // Dirty trick to control struct serialization :3
                    self,
                });
            }
        };

        // We are marking ouserlves also as an argument to manage struct serialization.
        pub const RedisArguments = struct {
            pub fn count(self: Self) usize {
                return comptime std.meta.fields(T).len;
            }

            pub fn serialize(self: Self, comptime rootSerializer: type, msg: var) !void {
                inline for (std.meta.fields(T)) |field| {
                    try rootSerializer.serializeArgument(msg, []const u8, field.name);
                }
            }
        };
    };
}

test "basic usage" {
    const cmd = HMGET.init("mykey", &[_][]const u8{ "field1", "field2" });
    try cmd.validate();

    const ExampleStruct = struct {
        banana: usize,
        id: []const u8,
    };

    const cmd1 = HMGET.forStruct(ExampleStruct).init("mykey");
    try cmd1.validate();
}
