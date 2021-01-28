pub const GEOADD = @import("./geo/geoadd.zig").GEOADD;
pub const GEODIST = @import("./geo/geodist.zig").GEODIST;
pub const GEOHASH = @import("./geo/geohash.zig").GEOHASH;
pub const GEOPOS = @import("./geo/geopos.zig").GEOPOS;
pub const GEORADIUS = @import("./geo/georadius.zig").GEORADIUS;
pub const GEORADIUSBYMEMBER = @import("./geo/georadiusbymember.zig").GEORADIUSBYMEMBER;

test "geo" {
    _ = @import("./geo/geoadd.zig");
    _ = @import("./geo/geodist.zig");
    _ = @import("./geo/geohash.zig");
    _ = @import("./geo/geopos.zig");
    _ = @import("./geo/georadius.zig");
    _ = @import("./geo/georadiusbymember.zig");
}

test "docs" {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
