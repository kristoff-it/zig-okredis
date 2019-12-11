const utils = @import("./utils/streams.zig");

/// XREAD [COUNT count] [BLOCK milliseconds] STREAMS key [key ...] ID [id ...]
pub const XREAD = struct {
    count: Count = .NoCount,
    block: Block = .NoBlock,
    streams: []const []const u8,
    ids: []const []const u8,

    /// Instantiates a new XREAD command.
    pub fn init(count: Count, block: Block, streams: []const []const u8, ids: []const []const u8) XREAD {
        return .{
            .count = count,
            .block = block,
            .streams = streams,
            .ids = ids,
        };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: XREAD) !void {
        // Zero means blocking forever.
        // Use `.Forever` in such case.
        switch (self.block) {
            else => {},
            .Milliseconds => |m| if (m == 0) return error.ZeroMeansBlockingForever,
        }

        // Check if the number of parameters is correct
        if (self.streams.len == 0) return error.StreamsArrayIsEmpty;
        if (self.streams.len != self.ids.len) return error.StreamsAndIDsLenMismatch;

        // Check the individual stream/id entries
        var i: usize = 0;
        while (i < self.streams.len) : (i += 1) {
            if (self.streams[i].len == 0) return error.EmptyKeyName;
            if (!utils.isValidStreamID(.XREAD, self.ids[i])) return error.InvalidID;
        }
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: XREAD, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{
                "XREAD",
                self.count,
                self.block,
                "STREAMS",
                self.streams,
                self.ids,
            });
        }
    };

    pub const Count = union(enum) {
        NoCount,
        Count: usize,

        pub const RedisArguments = struct {
            pub fn count(self: Count) usize {
                return switch (self) {
                    .NoCount => 0,
                    .Count => 2,
                };
            }

            pub fn serialize(self: Count, comptime rootSerializer: type, msg: var) !void {
                switch (self) {
                    .NoCount => {},
                    .Count => |c| {
                        try rootSerializer.serializeArgument(msg, []const u8, "COUNT");
                        try rootSerializer.serializeArgument(msg, u64, c);
                    },
                }
            }
        };
    };

    pub const Block = union(enum) {
        NoBlock,
        Forever,
        Milliseconds: usize,

        pub const RedisArguments = struct {
            pub fn count(self: Block) usize {
                return switch (self) {
                    .NoBlock => 0,
                    else => 2,
                };
            }

            pub fn serialize(self: Block, comptime rootSerializer: type, msg: var) !void {
                switch (self) {
                    .NoBlock => {},
                    .Forever => |m| {
                        try rootSerializer.serializeArgument(msg, []const u8, "BLOCK");
                        try rootSerializer.serializeArgument(msg, u64, 0);
                    },
                    .Milliseconds => |m| {
                        try rootSerializer.serializeArgument(msg, []const u8, "BLOCK");
                        try rootSerializer.serializeArgument(msg, u64, m);
                    },
                }
            }
        };
    };
};

test "basic usage" {
    const cmd = XREAD.init(
        .NoCount,
        .NoBlock,
        &[_][]const u8{ "stream1", "stream2" },
        &[_][]const u8{ "123-123", "$" },
    );

    try cmd.validate();
}
