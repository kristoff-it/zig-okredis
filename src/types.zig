const attributes = @import("./types/attributes.zig");
const verbatim = @import("./types/verbatim.zig");
const fixbuf = @import("./types/fixbuf.zig");
const reply = @import("./types/reply.zig");
const err = @import("./types/error.zig");

pub const WithAttribs = attributes.WithAttribs;
pub const Verbatim = verbatim.Verbatim;
pub const FixBuf = fixbuf.FixBuf;
pub const DynamicReply = reply.DynamicReply;
pub const OrFullErr = err.OrFullErr;
pub const OrErr = err.OrErr;

test "types" {
    _ = @import("./types/attributes.zig");
    _ = @import("./types/verbatim.zig");
    _ = @import("./types/fixbuf.zig");
    _ = @import("./types/reply.zig");
    _ = @import("./types/error.zig");
}

test "docs" {
    @import("std").testing.refAllDecls(@This());
}
