const std = @import("std");

pub const Client = @import("./client.zig");
pub const commands = @import("./commands.zig");
const parser = @import("./parser.zig");
pub const freeReply = parser.RESP3Parser.freeReply;
const serializer = @import("./serializer.zig");
pub const traits = @import("./traits.zig");
pub const types = @import("./types.zig");

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
