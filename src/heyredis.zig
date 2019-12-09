const client = @import("./client.zig");
const parser = @import("./parser.zig");
const types = @import("./types.zig");
const serializer = @import("./serializer.zig");

pub const commands = @import("./commands.zig");
pub const freeReply = parser.RESP3Parser.freeReply;
pub const DynamicReply = types.DynamicReply;
pub const OrFullErr = types.OrFullErr;
pub const Client = client.Client;
pub const FixBuf = types.FixBuf;
pub const OrErr = types.OrErr;
pub const KV = types.KV;

test "heyredis" {
    _ = @import("./client.zig");
    _ = @import("./parser.zig");
    _ = @import("./types.zig");
    _ = @import("./serializer.zig");
}
