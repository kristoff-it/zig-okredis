pub const HMGET = @import("./hashes/hmget.zig").HMGET;
pub const HSET = @import("./hashes/hset.zig").HSET;
pub const HINCRBY = @import("./hashes/hincrby.zig").HINCRBY;

pub const utils = struct {
    pub const FV = @import("./_common_utils.zig").FV;
};

test "hashes" {
    _ = @import("./hashes/hmget.zig");
    _ = @import("./hashes/hset.zig");
    _ = @import("./hashes/hincrby.zig");
}

test "docs" {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
