pub const APPEND = @import("./strings/append.zig").APPEND;
pub const BITCOUNT = @import("./strings/bitcount.zig").BITCOUNT;
// pub const BITFIELD = @import("./strings/bitfield.zig").BITFIELD;
pub const BITOP = @import("./strings/bitop.zig").BITOP;
pub const BITPOS = @import("./strings/bitpos.zig").BITPOS;
pub const DECR = @import("./strings/decr.zig").DECR;
pub const DECRBY = @import("./strings/decrby.zig").DECRBY;
pub const GET = @import("./strings/get.zig").GET;
pub const GETBIT = @import("./strings/getbit.zig").GETBIT;
pub const GETRANGE = @import("./strings/getrange.zig").GETRANGE;
pub const GETSET = @import("./strings/getset.zig").GETSET;
pub const INCR = @import("./strings/incr.zig").INCR;
pub const INCRBY = @import("./strings/incrby.zig").INCRBY;
pub const INCRBYFLOAT = @import("./strings/incrbyfloat.zig").INCRBYFLOAT;
pub const MGET = @import("./strings/mget.zig").MGET;
// pub const MSET = @import("./strings/mset.zig").MSET;
// pub const MSETNX = @import("./strings/msetnx.zig").MSETNX;
// pub const PSETEX = @import("./strings/psetex.zig").PSETEX;
pub const SET = @import("./strings/set.zig").SET;
pub const SETBIT = @import("./strings/setbit.zig").SETBIT;
pub const utils = struct {
    pub const Value = @import("./_common_utils.zig").Value;
};

test "strings" {
    _ = @import("./strings/append.zig");
    _ = @import("./strings/bitcount.zig");
    _ = @import("./strings/bitfield.zig");
    _ = @import("./strings/bitop.zig");
    _ = @import("./strings/bitpos.zig");
    _ = @import("./strings/decr.zig");
    _ = @import("./strings/decrby.zig");
    _ = @import("./strings/get.zig");
    _ = @import("./strings/getbit.zig");
    _ = @import("./strings/getrange.zig");
    _ = @import("./strings/getset.zig");
    _ = @import("./strings/incr.zig");
    _ = @import("./strings/incrby.zig");
    _ = @import("./strings/incrbyfloat.zig");
    _ = @import("./strings/mget.zig");
    _ = @import("./strings/mset.zig");
    _ = @import("./strings/msetnx.zig");
    _ = @import("./strings/psetex.zig");
    _ = @import("./strings/set.zig");
    _ = @import("./strings/setbit.zig");
}

test "docs" {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
