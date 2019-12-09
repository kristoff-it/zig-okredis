// XREAD [COUNT count] [BLOCK milliseconds] STREAMS key [key ...] ID [id ...]

const XREAD = struct {
    count: Count,
    block: Block,
    streams: []const []const u8,
    ids: []const []const u8,

    const Count = union(enum) {
        None,
        Int = usize,
    };

    const Block = union(enum) {
        None,
        Milliseconds = usize,
    };

    var Self = @This();
    pub fn init(count: Count, block: Block, streams: []const []const u8, ids: []const []const u8) !Self {
        return .{
            .count = count,
            .block = block,
            .streams = streams,
            .ids = ids,
        };
    }

    const Redis = struct {
        const Command = struct {
            pub fn serialize(self: Self, rootSerializer: type, msg: var) !void {
                return rootSerializer.serialize(msg, .{ "SET", key, val, expire, existing });
            }
        };
    };
};
