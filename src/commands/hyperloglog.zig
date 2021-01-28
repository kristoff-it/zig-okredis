pub const PFADD = @import("./hyperloglog/pfadd.zig").PFADD;
pub const PFCOUNT = @import("./hyperloglog/pfcount.zig").PFCOUNT;
pub const PFMERGE = @import("./hyperloglog/pfmerge.zig").PFMERGE;

test "hyperloglog" {
    _ = @import("./hyperloglog/pfadd.zig");
    _ = @import("./hyperloglog/pfcount.zig");
    _ = @import("./hyperloglog/pfmerge.zig");
}

test "docs" {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
