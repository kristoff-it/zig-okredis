pub const XADD = @import("./streams/xadd.zig").XADD;
pub const XREAD = @import("./streams/xread.zig").XREAD;
pub const XTRIM = @import("./streams/xtrim.zig").XTRIM;
pub const utils = struct {
    pub const FV = @import("./_common_utils.zig").FV;
};

test "streams" {
    _ = @import("./streams/xadd.zig");
    _ = @import("./streams/xread.zig");
    _ = @import("./streams/xtrim.zig");
}

test "docs" {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
