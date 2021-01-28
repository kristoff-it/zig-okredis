const std = @import("std");
const client = @import("./client.zig");
const parser = @import("./parser.zig");
const serializer = @import("./serializer.zig");

pub const commands = @import("./commands.zig");
pub const types = @import("./types.zig");
pub const traits = @import("./traits.zig");
pub const freeReply = parser.RESP3Parser.freeReply;
pub const Client = client.Client;
pub const BufferedClient = client.BufferedClient;

test "okredis" {
    _ = @import("./client.zig");
    _ = @import("./parser.zig");
    _ = @import("./types.zig");
    _ = @import("./serializer.zig");
    _ = @import("./commands.zig");
}

test "docs" {
    std.testing.refAllDecls(@This());
}
