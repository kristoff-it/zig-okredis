pub const SADD = @import("./sets/sadd.zig").SADD;
pub const SINTER = @import("./sets/sinter.zig").SINTER;
pub const SMISMEMBER = @import("./sets/smismember.zig").SMISMEMBER;
pub const SREM = @import("./sets/srem.zig").SREM;
pub const SCARD = @import("./sets/scard.zig").SCARD;
pub const SINTERSTORE = @import("./sets/sinterstore.zig").SINTERSTORE;
pub const SMOVE = @import("./sets/smove.zig").SMOVE;
pub const SSCAN = @import("./sets/sscan.zig").SSCAN;
pub const SDIFF = @import("./sets/sdiff.zig").SDIFF;
pub const SISMEMBER = @import("./sets/sismember.zig").SISMEMBER;
pub const SPOP = @import("./sets/spop.zig").SPOP;
pub const SUNION = @import("./sets/sunion.zig").SUNION;
pub const SDIFFSTORE = @import("./sets/sdiffstore.zig").SDIFFSTORE;
pub const SMEMBERS = @import("./sets/smembers.zig").SMEMBERS;
pub const SRANDMEMBER = @import("./sets/srandmember.zig").SRANDMEMBER;
pub const SUNIONSTORE = @import("./sets/sunionstore.zig").SUNIONSTORE;

test "sets" {
    _ = @import("./sets/sadd.zig");
    _ = @import("./sets/sinter.zig");
    _ = @import("./sets/smismember.zig");
    _ = @import("./sets/srem.zig");
    _ = @import("./sets/scard.zig");
    _ = @import("./sets/sinterstore.zig");
    _ = @import("./sets/smove.zig");
    _ = @import("./sets/sscan.zig");
    _ = @import("./sets/sdiff.zig");
    _ = @import("./sets/sismember.zig");
    _ = @import("./sets/spop.zig");
    _ = @import("./sets/sunion.zig");
    _ = @import("./sets/sdiffstore.zig");
    _ = @import("./sets/smembers.zig");
    _ = @import("./sets/srandmember.zig");
    _ = @import("./sets/sunionstore.zig");
}

test "docs" {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
