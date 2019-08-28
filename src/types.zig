const attributes = @import("./types/attributes.zig");
const verbatim = @import("./types/verbatim.zig");
const fixbuf = @import("./types/fixbuf.zig");
const reply = @import("./types/reply.zig");
const err = @import("./types/error.zig");
const kv = @import("./types/kv.zig");

pub const DynamicReply = reply.DynamicReply;
pub const WithAttribs = reply.WithAttribs;
pub const Verbatim = verbatim.Verbatim;
pub const OrFullErr = err.OrFullErr;
pub const FixBuf = fixbuf.FixBuf;
pub const OrErr = err.OrErr;
pub const KV = kv.KV;

test "types" {
    _ = @import("./types/attributes.zig");
    _ = @import("./types/verbatim.zig");
    _ = @import("./types/fixbuf.zig");
    _ = @import("./types/reply.zig");
    _ = @import("./types/error.zig");
    _ = @import("./types/kv.zig");
}
