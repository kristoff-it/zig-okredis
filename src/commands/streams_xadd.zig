/// XADD key id [MAXLEN [~] count] field value [field value ...]
const std = @import("std");
const utils = @import("./utils/streams.zig");
const common = @import("./utils/common.zig");
const KV = common.KV;

pub const XADD = struct {
    key: []const u8,
    id: []const u8,
    maxlen: MaxLen = .NoMaxLen,
    kvs: []const KV,

    /// Instantiates a new XADD command.
    pub fn init(key: []const u8, id: []const u8, maxlen: MaxLen, kvs: []const KV) XADD {
        return .{ .key = key, .id = id, .maxlen = maxlen, .kvs = kvs };
    }

    // This reassignment is necessary to avoid having two definitions of
    // RedisCommand in the same scope (it causes a shadowing error).
    pub const forStruct = _forStruct;

    /// Validates if the command is syntactically correct.
    pub fn validate(self: XADD) !void {
        if (self.kvs.len == 0) return error.KVsArrayIsEmpty;
        if (self.key.len == 0) return error.EmptyKeyName;
        if (!utils.isValidStreamID(.XADD, self.id)) return error.InvalidID;

        // Check the individual KV pairs
        // TODO: how the hell do I check for dups without an allocator?
        var i: usize = 0;
        while (i < self.kvs.len) : (i += 1) {
            if (self.kvs[i].key.len == 0) return error.EmptyKeyName;
        }
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: XADD, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{
                "XADD",
                self.key,
                self.id,
                self.maxlen,
                self.kvs,
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

            pub fn serialize(self: MaxLen, comptime rootSerializer: type, msg: var) !void {
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
    if (@typeId(T) != .Struct) @compileError("Only Struct types allowed.");
    return struct {
        key: []const u8,
        id: []const u8,
        maxlen: XADD.MaxLen,
        value: T,

        const Self = @This();
        pub fn init(key: []const u8, id: []const u8, maxlen: XADD.MaxLen, value: T) Self {
            return .{ .key = key, .id = id, .maxlen = maxlen, .value = value };
        }

        pub fn validate(self: Self) !void {
            if (self.key.len == 0) return error.EmptyKeyName;
            if (!utils.isValidStreamID(.XADD, self.id)) return error.InvalidID;
        }

        pub const RedisCommand = struct {
            pub fn serialize(self: Self, comptime rootSerializer: type, msg: var) !void {
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
            pub fn count(self: Self) usize {
                return comptime std.meta.fields(T).len * 2;
            }

            pub fn serialize(self: Self, comptime rootSerializer: type, msg: var) !void {
                inline for (std.meta.fields(T)) |field| {
                    const arg = @field(self.value, field.name);
                    const ArgT = @TypeOf(arg);
                    try rootSerializer.serializeArgument(msg, []const u8, field.name);
                    try rootSerializer.serializeArgument(msg, ArgT, arg);
                }
            }
        };
    };
}

test "basic usage" {
    const cmd = XADD.init("mykey", "*", .NoMaxLen, &[_]KV{
        .{ .key = "field1", .value = "val1" },
        .{ .key = "field2", .value = "val2" },
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
