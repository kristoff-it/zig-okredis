/// XADD key id [MAXLEN [~] count] field value [field value ...]
const std = @import("std");
const utils = @import("./_utils.zig");
const common = @import("../_common_utils.zig");
const FV = common.FV;

pub const XADD = struct {
    //! Command builder for XADD.
    //!
    //! Use `XADD.forStruct(T)` to create at `comptime` a specialized version of XADD
    //! whose `.init` accepts a struct for your choosing instead of `fvs`.
    //!
    //! ```
    //! const cmd = XADD.init("mykey", "*", .NoMaxLen, &[_]FV{
    //!     .{ .field = "field1", .value = "val1" },
    //!     .{ .field = "field2", .value = "val2" },
    //! });
    //!
    //! const ExampleStruct = struct {
    //!     banana: usize,
    //!     id: []const u8,
    //! };
    //!
    //! const example = ExampleStruct{
    //!     .banana = 10,
    //!     .id = "ok",
    //! };
    //!
    //! const MyXADD = XADD.forStruct(ExampleStruct);
    //!
    //! const cmd1 = MyXADD.init("mykey", "*", .NoMaxLen, example);
    //! ```

    key: []const u8,
    id: []const u8,
    maxlen: MaxLen = .NoMaxLen,
    fvs: []const FV,

    /// Instantiates a new XADD command.
    pub fn init(key: []const u8, id: []const u8, maxlen: MaxLen, fvs: []const FV) XADD {
        return .{ .key = key, .id = id, .maxlen = maxlen, .fvs = fvs };
    }

    /// Type constructor that creates a specialized version of XADD whose
    /// .init accepts a struct for your choosing instead of `fvs`.
    pub const forStruct = _forStruct;
    // This reassignment is necessary to avoid having two definitions of
    // RedisCommand in the same scope (it causes a shadowing error).

    /// Validates if the command is syntactically correct.
    pub fn validate(self: XADD) !void {
        if (self.key.len == 0) return error.EmptyKeyName;
        if (self.fvs.len == 0) return error.FVsArrayIsEmpty;
        if (!utils.isValidStreamID(.XADD, self.id)) return error.InvalidID;

        // Check the individual KV pairs
        // TODO: how the hell do I check for dups without an allocator?
        var i: usize = 0;
        while (i < self.fvs.len) : (i += 1) {
            if (self.fvs[i].field.len == 0) return error.EmptyFieldName;
        }
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: XADD, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{
                "XADD",
                self.key,
                self.id,
                self.maxlen,
                self.fvs,
            });
        }
    };

    pub const MaxLen = union(enum) {
        NoMaxLen,
        MaxLen: u64,
        PreciseMaxLen: u64,

        pub const RedisArguments = struct {
            pub fn count(self: MaxLen) usize {
                return switch (self) {
                    .NoMaxLen => 0,
                    .MaxLen => 3,
                    .PreciseMaxLen => 2,
                };
            }

            pub fn serialize(self: MaxLen, comptime rootSerializer: type, msg: anytype) !void {
                switch (self) {
                    .NoMaxLen => {},
                    .MaxLen => |c| {
                        try rootSerializer.serializeArgument(msg, []const u8, "MAXLEN");
                        try rootSerializer.serializeArgument(msg, []const u8, "~");
                        try rootSerializer.serializeArgument(msg, u64, c);
                    },
                    .PreciseMaxLen => |c| {
                        try rootSerializer.serializeArgument(msg, []const u8, "MAXLEN");
                        try rootSerializer.serializeArgument(msg, u64, c);
                    },
                }
            }
        };
    };
};

fn _forStruct(comptime T: type) type {
    // TODO: support pointers to struct, check that the struct is serializable (strings and numbers).
    if (@typeInfo(T) != .Struct) @compileError("Only Struct types allowed.");
    return struct {
        key: []const u8,
        id: []const u8,
        maxlen: XADD.MaxLen,
        values: T,

        const Self = @This();
        pub fn init(key: []const u8, id: []const u8, maxlen: XADD.MaxLen, values: T) Self {
            return .{ .key = key, .id = id, .maxlen = maxlen, .values = values };
        }

        pub fn validate(self: Self) !void {
            if (self.key.len == 0) return error.EmptyKeyName;
            if (!utils.isValidStreamID(.XADD, self.id)) return error.InvalidID;
        }

        pub const RedisCommand = struct {
            pub fn serialize(self: Self, comptime rootSerializer: type, msg: anytype) !void {
                return rootSerializer.serializeCommand(msg, .{
                    "XADD",
                    self.key,
                    self.id,
                    self.maxlen,

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
    const cmd = XADD.init("mykey", "*", .NoMaxLen, &[_]FV{
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

    const cmd1 = XADD.forStruct(ExampleStruct).init("mykey", "*", .NoMaxLen, example);
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
                XADD.init("k1", "1-1", .NoMaxLen, &[_]FV{.{ .field = "f1", .value = "v1" }}),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "XADD", "k1", "1-1", "f1", "v1" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            // try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            const MyStruct = struct {
                field1: []const u8,
                field2: u8,
                field3: usize,
            };

            const MyXADD = XADD.forStruct(MyStruct);

            try serializer.serializeCommand(
                testMsg.writer(),
                MyXADD.init("k1", "1-1", .NoMaxLen, .{ .field1 = "nice!", .field2 = 'a', .field3 = 42 }),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "XADD", "k1", "1-1", "field1", "nice!", "field2", 'a', "field3", 42 },
            );

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

            const MyXADD = XADD.forStruct(MyStruct);

            try serializer.serializeCommand(
                testMsg.writer(),
                MyXADD.init(
                    "k1",
                    "1-1",
                    XADD.MaxLen{ .PreciseMaxLen = 40 },
                    .{ .field1 = "nice!", .field2 = 'a', .field3 = 42 },
                ),
            );
            try serializer.serializeCommand(
                correctMsg.writer(),
                .{ "XADD", "k1", "1-1", "MAXLEN", 40, "field1", "nice!", "field2", 'a', "field3", 42 },
            );

            try std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
