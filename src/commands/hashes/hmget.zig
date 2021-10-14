// HMGET key field [field ...]

const std = @import("std");
const common = @import("../_common_utils.zig");
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
        pub fn serialize(self: HMGET, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "HMGET", self.key, self.fields });
        }
    };
};

fn _forStruct(comptime T: type) type {
    // TODO: there is some duplicated code with xread. Values should be a dedicated generic type.
    if (@typeInfo(T) != .Struct) @compileError("Only Struct types allowed.");
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
            pub fn serialize(self: Self, comptime rootSerializer: type, msg: anytype) !void {
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
            pub fn count(_: Self) usize {
                return comptime std.meta.fields(T).len;
            }

            pub fn serialize(_: Self, comptime rootSerializer: type, msg: anytype) !void {
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

test "serializer" {
    const serializer = @import("../../serializer.zig").CommandSerializer;

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.fixedBufferStream(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.fixedBufferStream(testBuf[0..]);

    {
        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                testMsg.writer(),
                HMGET.init("k1", &[_][]const u8{"f1"}),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "HMGET", "k1", "f1" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            const MyStruct = struct {
                field1: []const u8,
                field2: u8,
                field3: usize,
            };

            const MyHMGET = HMGET.forStruct(MyStruct);

            try serializer.serializeCommand(
                testMsg.writer(),
                MyHMGET.init("k1"),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "HMGET", "k1", "field1", "field2", "field3" },
            );

            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
