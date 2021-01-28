pub const DEL = @import("./keys/del.zig").DEL;

test "keys" {
    _ = @import("./keys/del.zig");
}

test "docs" {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
