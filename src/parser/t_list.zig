const std = @import("std");
const Reader = std.Io.Reader;
const fmt = std.fmt;
const builtin = @import("builtin");

/// Parses RedisList values.
/// Uses RESP3Parser to delegate parsing of the list contents recursively.
pub const ListParser = struct {
    // TODO: prevent users from unmarshaling structs out of strings
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .array => true,
            .@"struct" => |stc| {
                for (stc.fields) |f|
                    if (f.type == *anyopaque)
                        return false;
                return true;
            },
            else => false,
        };
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .pointer => true,
            else => isSupported(T),
        };
    }

    pub fn parse(comptime T: type, comptime rootParser: type, r: *Reader) !T {
        return parseImpl(T, rootParser, .{}, r);
    }
    pub fn parseAlloc(
        comptime T: type,
        comptime rootParser: type,
        allocator: std.mem.Allocator,
        r: *Reader,
    ) !T {
        return parseImpl(T, rootParser, .{ .ptr = allocator }, r);
    }

    fn decodeArray(
        comptime T: type,
        result: []T,
        rootParser: anytype,
        allocator: anytype,
        r: *Reader,
    ) !void {
        var foundNil = false;
        var foundErr = false;
        for (result) |*elem| {
            if (foundNil or foundErr) {
                rootParser.parse(void, r) catch |err| switch (err) {
                    error.GotErrorReply => {
                        foundErr = true;
                    },
                    else => return err,
                };
            } else {
                elem.* = (if (@hasField(@TypeOf(allocator), "ptr"))
                    rootParser.parseAlloc(T, allocator.ptr, r)
                else
                    rootParser.parse(T, r)) catch |err| switch (err) {
                    error.GotNilReply => {
                        foundNil = true;
                        continue;
                    },
                    error.GotErrorReply => {
                        foundErr = true;
                        continue;
                    },
                    else => return err,
                };
            }
        }

        // Error takes precedence over Nil
        if (foundErr) return error.GotErrorReply;
        if (foundNil) return error.GotNilReply;
        return;
    }

    pub fn parseImpl(comptime T: type, comptime rootParser: type, allocator: anytype, r: *Reader) !T {
        // TODO: write real implementation
        var buf: [100]u8 = undefined;
        var end: usize = 0;
        for (&buf, 0..) |*elem, i| {
            const ch = try r.takeByte();
            elem.* = ch;
            if (ch == '\r') {
                end = i;
                break;
            }
        }
        try r.discardAll(1);
        const size = try fmt.parseInt(usize, buf[0..end], 10);

        switch (@typeInfo(T)) {
            else => unreachable,
            .pointer => |ptr| {
                if (!@hasField(@TypeOf(allocator), "ptr")) {
                    @compileError("To decode a slice you need to use sendAlloc / pipeAlloc / transAlloc!");
                }

                const result = try allocator.ptr.alloc(ptr.child, size);
                errdefer allocator.ptr.free(result);
                try decodeArray(ptr.child, result, rootParser, allocator, r);
                return result;
            },
            .array => |arr| {
                if (arr.len != size) {
                    // The user requested an array but the list reply from Redis
                    // contains a different amount of items.
                    var foundErr = false;
                    var i: usize = 0;
                    while (i < size) : (i += 1) {
                        // Discard all the items
                        rootParser.parse(void, r) catch |err| switch (err) {
                            error.GotErrorReply => {
                                foundErr = true;
                            },
                            else => return err,
                        };
                    }

                    // GotErrorReply takes precedence over LengthMismatch
                    if (foundErr) return error.GotErrorReply;
                    return error.LengthMismatch;
                }

                var result: T = undefined;
                try decodeArray(arr.child, result[0..], rootParser, allocator, r);
                return result;
            },
            .@"struct" => |stc| {
                var foundNil = false;
                var foundErr = false;
                if (stc.fields.len != size) {
                    // The user requested a struct but the list reply from Redis
                    // contains a different amount of items.
                    var i: usize = 0;
                    while (i < size) : (i += 1) {
                        // Discard all the items
                        rootParser.parse(void, r) catch |err| switch (err) {
                            error.GotErrorReply => {
                                foundErr = true;
                            },
                            else => return err,
                        };
                    }

                    // GotErrorReply takes precedence over LengthMismatch
                    if (foundErr) return error.GotErrorReply;
                    return error.LengthMismatch;
                }

                var result: T = undefined;
                inline for (stc.fields) |field| {
                    if (foundNil or foundErr) {
                        rootParser.parse(void, r) catch |err| switch (err) {
                            error.GotErrorReply => {
                                foundErr = true;
                            },
                            else => return err,
                        };
                    } else {
                        @field(result, field.name) = (if (@hasField(@TypeOf(allocator), "ptr"))
                            rootParser.parseAlloc(field.type, allocator.ptr, r)
                        else
                            rootParser.parse(field.type, r)) catch |err| switch (err) {
                            else => return err,
                            error.GotNilReply => blk: {
                                foundNil = true;
                                break :blk undefined; // I don't think I can continue here, given the inlining.
                            },
                            error.GotErrorReply => blk: {
                                foundErr = true;
                                break :blk undefined;
                            },
                        };
                    }
                }
                if (foundErr) return error.GotErrorReply;
                if (foundNil) return error.GotNilReply;
                return result;
            },
        }
    }
};
