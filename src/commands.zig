pub const hyperloglog = @import("./commands/hyperloglog.zig");
pub const strings = @import("./commands/strings.zig");
pub const streams = @import("./commands/streams.zig");
pub const hashes = @import("./commands/hashes.zig");
pub const keys = @import("./commands/keys.zig");
pub const sets = @import("./commands/sets.zig");
pub const geo = @import("./commands/geo.zig");

// These are all command builders than can be used interchangeably with the main syntax:
// ```
// try client.send(void, .{"SET", "key", 42});
// try client.send(void, SET.init("key", 42, .NoExpire, .NoConditions));
// ```
// Command builders offer more comptime safety through their `.init` functions and
// most of them also feature a `.validate()` method that performs semantic validation.
//
// The `.validate()` method can be run at comptime for command instances that don't
// depend on runtime data, ensuring correctness without impacting runtime performance.

test "commands" {
    _ = @import("./commands/hyperloglog.zig");
    _ = @import("./commands/strings.zig");
    _ = @import("./commands/streams.zig");
    _ = @import("./commands/hashes.zig");
    _ = @import("./commands/keys.zig");
    _ = @import("./commands/sets.zig");
    _ = @import("./commands/geo.zig");
}

test "docs" {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
