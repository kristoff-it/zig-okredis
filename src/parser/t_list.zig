const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;

/// Parses RedisList values.
/// Uses RESP3Parser to delegate parsing of the list contents recursively.
pub const ListParser = struct {
    // TODO: prevent users from unmarshaling structs out of strings
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeId(T)) {
            .Array, .Struct => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime rootParser: type, msg: var) !T {
        // TODO: write real implementation
        var buf: [100]u8 = undefined;
        var end: usize = 0;
        for (buf) |*elem, i| {
            const ch = try msg.readByte();
            elem.* = ch;
            if (ch == '\r') {
                end = i;
                break;
            }
        }
        try msg.skipBytes(1);
        const size = try fmt.parseInt(usize, buf[0..end], 10);

        switch (@typeInfo(T)) {
            // TODO: deduplicate the work done for array in parse and parsealloc
            .Array => |arr| {
                if (arr.len != size) {
                    return error.LengthMismatch;
                }

                var result: T = undefined;
                var foundNil = false;
                var foundErr = false;
                for (result) |*elem| {
                    if (foundNil or foundErr) {
                        rootParser.parse(void, msg) catch |err| switch (err) {
                            // Void is not part of the errorset because
                            // .parse redirects us immediately to the void parser.
                            // error.GotNilReply => {},
                            error.GotErrorReply => {
                                foundErr = true;
                            },
                            else => return err,
                        };
                    } else {
                        elem.* = rootParser.parse(arr.child, msg) catch |err| switch (err) {
                            else => return err,
                            // TODO
                            // error.GotNilReply => {
                            //     foundNil = true;
                            //     continue;
                            // },
                            error.GotErrorReply => {
                                foundErr = true;
                                continue;
                            },
                        };
                    }
                }

                if (foundErr) return error.GotErrorReply;
                if (foundNil) return error.GotNilReply;
                return result;
            },
            .Struct => |stc| {
                if (stc.fields.len != size) {
                    return error.LengthMismatch;
                }

                var result: T = undefined;
                var foundNil = false;
                var foundErr = false;
                inline for (stc.fields) |field| {
                    @field(result, field.name) = rootParser.parse(field.field_type, msg) catch |err| switch (err) {
                        else => return err,
                        // TODO
                        // error.GotNilReply => blk: {
                        //     foundNil = true;
                        //     break :blk undefined;
                        // },
                        error.GotErrorReply => blk: {
                            foundErr = true;
                            break :blk undefined;
                        },
                    };
                }
                if (foundErr) return error.GotErrorReply;
                if (foundNil) return error.GotNilReply;
                return result;
            },
            else => @compileError("Unhandled Conversion"),
        }
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Array, .Pointer => true,
            else => false,
        };
    }

    pub fn parseAlloc(comptime T: type, comptime rootParser: type, allocator: *std.mem.Allocator, msg: var) !T {
        // TODO: write real implementation
        var buf: [100]u8 = undefined;
        var end: usize = 0;
        for (buf) |*elem, i| {
            const ch = try msg.readByte();
            elem.* = ch;
            if (ch == '\r') {
                end = i;
                break;
            }
        }

        try msg.skipBytes(1);
        const size = try fmt.parseInt(usize, buf[0..end], 10);

        switch (@typeInfo(T)) {
            .Pointer => |ptr| {
                var res = try allocator.alloc(ptr.child, size);
                errdefer allocator.free(res);

                for (res) |*elem| {
                    elem.* = try rootParser.parseAlloc(ptr.child, allocator, msg);
                }

                return res;
            },
            .Array => |arr| {
                if (arr.len != size) {
                    return error.LengthMismatch;
                }
                var result: T = undefined;
                for (result) |*elem| {
                    elem.* = try rootParser.parseAlloc(arr.child, allocator, msg);
                }
                return result;
            },
            else => @compileError("Unhandled Conversion"),
        }
    }
};
