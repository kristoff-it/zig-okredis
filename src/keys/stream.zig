const Key = @import("./key.zig");
const cmds = @import("../commands.zig");

const Stream = struct {
    key: Key,

    pub fn init(key_name: []const u8) Stream {
        return Stream{Key{key_name}};
    }

    pub fn xadd(self: Stream, id: u8, fvs: []cmds.streams.utils.FV) XADD {}
    pub fn xaddStruct(comptime T: type, self: Stream, id: u8, data: T) XADD.forStruct(T) {} // maybe var?

    pub fn xread(count: Count, block: Block, id: []const u8) void {}
    pub fn xreadStruct(comptime T: type, count: Count, block: Block, id: []const u8) XREAD.forStruct(T) {}

    pub fn xtrim() void {}
};

test "usage" {
    const Stream = okredis.keys.Stream;

    temperatures = Stream.init("temps");
    last_hour = temperatures.xread(30, .NoBlock, "123");

    const MyTemp = struct {
        temperature: float64,
        humidity: float64,
    };

    last_hour = temperatures.xreadStruct(MyTemp, 30, .NoBlock, "123");
}

const StreamConsumer = struct {
    keys: []const u8,

    pub fn ensure() void {}
};
