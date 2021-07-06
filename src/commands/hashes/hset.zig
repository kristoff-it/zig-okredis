// HSET key field value [field value ...]

const std = @import("std");
const common = @import("../_common_utils.zig");
const FV = common.FV;

pub const HSET = struct {
    key: []const u8,
    fvs: []const FV,

    /// Instantiates a new HSET command.
    pub fn init(key: []const u8, fvs: []const FV) HSET {
        return .{ .key = key, .fvs = fvs };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: HSET) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
        if (self.fvs.len == 0) return error.FVsArrayIsEmpty;

        // Check the individual FV pairs
        // TODO: how the hell do I check for dups without an allocator?
        var i: usize = 0;
        while (i < self.fvs.len) : (i += 1) {
            if (self.fvs[i].field.len == 0) return error.EmptyFieldName;
        }
    }

    // This reassignment is necessary to avoid having two definitions of
    // RedisCommand in the same scope (it causes a shadowing error).
    pub const forStruct = _forStruct;

    pub const RedisCommand = struct {
        pub fn serialize(self: HSET, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "HSET", self.key, self });
        }
    };

    pub const RedisArguments = struct {
        pub fn count(self: HSET) usize {
            return self.fvs.len * 2;
        }

        pub fn serialize(self: HSET, comptime rootSerializer: type, msg: anytype) !void {
            for (self.fvs) |fv| {
                try rootSerializer.serializeArgument(msg, []const u8, fv.field);
                try rootSerializer.serializeArgument(msg, []const u8, fv.value);
            }
        }
    };
};

fn _forStruct(comptime T: type) type {
    // TODO: support pointers to struct, check that the struct is serializable (strings and numbers).
    // TODO: there is some duplicated code with xread. Values should be a dedicated generic type.
    if (@typeInfo(T) != .Struct) @compileError("Only Struct types allowed.");
    return struct {
        key: []const u8,
        values: T,

        const Self = @This();
        pub fn init(key: []const u8, values: T) Self {
            return .{ .key = key, .values = values };
        }

        /// Validates if the command is syntactically correct.
        pub fn validate(self: Self) !void {
            if (self.key.len == 0) return error.EmptyKeyName;
        }

        pub const RedisCommand = struct {
            pub fn serialize(self: Self, comptime rootSerializer: type, msg: anytype) !void {
                return rootSerializer.serializeCommand(msg, .{
                    "HSET",
                    self.key,

                    // Dirty trick to control struct serialization :3
                    self,
                });
            }
        };

        // We are marking ouserlves also as an argument to manage struct serialization.
        pub const RedisArguments = struct {
            pub fn count(_: Self) usize {
                return comptime std.meta.fields(T).len * 2;
            }

            pub fn serialize(self: Self, comptime rootSerializer: type, msg: anytype) !void {
                inline for (std.meta.fields(T)) |field| {
                    const arg = @field(self.values, field.name);
                    const ArgT = @TypeOf(arg);
                    try rootSerializer.serializeArgument(msg, []const u8, field.name);
                    try rootSerializer.serializeArgument(msg, ArgT, arg);
                }
            }
        };
    };
}

test "basic usage" {
    const cmd = HSET.init("mykey", &[_]FV{
        .{ .field = "field1", .value = "val1" },
        .{ .field = "field2", .value = "val2" },
    });
    try cmd.validate();

    const ExampleStruct = struct {
        banana: usize,
        id: []const u8,
    };

    const example = ExampleStruct{
        .banana = 10,
        .id = "ok",
    };

    const cmd1 = HSET.forStruct(ExampleStruct).init("mykey", example);
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
                HSET.init("k1", &[_]FV{.{ .field = "f1", .value = "v1" }}),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "HSET", "k1", "f1", "v1" },
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

            const MyHSET = HSET.forStruct(MyStruct);

            try serializer.serializeCommand(
                testMsg.writer(),
                MyHSET.init(
                    "k1",
                    .{ .field1 = "nice!", .field2 = 'a', .field3 = 42 },
                ),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "HSET", "k1", "field1", "nice!", "field2", 'a', "field3", 42 },
            );

            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
