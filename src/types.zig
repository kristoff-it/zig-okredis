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

//! These are custom types that implement custom decoding logic.
//!
//! - `OrErr(T)` is a type that can decode error replies from Redis.
//! - `FixBuf(N)` is an array + length for decoding variable-length string replies from Redis without needing an allocator.
//! - `Verbatim` decodes strings from Redis and keeps track of metadata like wether the string is of a special type (e.g. markdown)
//! - `DynamicReply` is a union that can represent any possible reply from Redis, useful for when you don't know what Redis will send to you (e.g. interactive clients).

test "types" {
    _ = @import("./types/attributes.zig");
    _ = @import("./types/verbatim.zig");
    _ = @import("./types/fixbuf.zig");
    _ = @import("./types/reply.zig");
    _ = @import("./types/error.zig");
}

test "docs" {
    @import("std").meta.refAllDecls(@This());
}
