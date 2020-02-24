pub const strings = @import("./commands/strings.zig");
pub const streams = @import("./commands/streams.zig");
pub const hashes = @import("./commands/hashes.zig");

test "commands" {
    _ = @import("./commands/strings.zig");
    _ = @import("./commands/streams.zig");
    _ = @import("./commands/hashes.zig");
}
