const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;

/// Parses RedisList values.
/// Uses RESP3Parser to delegate parsing of the list contents recursively.
pub const ListParser = struct {
    // TODO: prevent users from unmarshaling structs out of strings
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Array => true,
            .Struct => |stc| {
                for (stc.fields) |f|
                    if (f.field_type == *anyopaque)
                        return false;
                return true;
            },
            else => false,
        };
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Pointer => true,
            else => isSupported(T),
        };
    }

    pub fn parse(comptime T: type, comptime rootParser: type, msg: anytype) !T {
        return parseImpl(T, rootParser, .{}, msg);
    }
    pub fn parseAlloc(comptime T: type, comptime rootParser: type, allocator: std.mem.Allocator, msg: anytype) !T {
        return parseImpl(T, rootParser, .{ .ptr = allocator }, msg);
    }

    fn decodeArray(comptime T: type, result: []T, rootParser: anytype, allocator: anytype, msg: anytype) !void {
        var foundNil = false;
        var foundErr = false;
        for (result) |*elem| {
            if (foundNil or foundErr) {
                rootParser.parse(void, msg) catch |err| switch (err) {
                    error.GotErrorReply => {
                        foundErr = true;
                    },
                    else => return err,
                };
            } else {
                elem.* = (if (@hasField(@TypeOf(allocator), "ptr"))
                    rootParser.parseAlloc(T, allocator.ptr, msg)
                else
                    rootParser.parse(T, msg)) catch |err| switch (err) {
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

    pub fn parseImpl(comptime T: type, comptime rootParser: type, allocator: anytype, msg: anytype) !T {
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
        try msg.skipBytes(1, .{});
        const size = try fmt.parseInt(usize, buf[0..end], 10);

        switch (@typeInfo(T)) {
            else => unreachable,
            .Pointer => |ptr| {
                if (!@hasField(@TypeOf(allocator), "ptr")) {
                    @compileError("To decode a slice you need to use sendAlloc / pipeAlloc / transAlloc!");
                }

                var result = try allocator.ptr.alloc(ptr.child, size);
                errdefer allocator.ptr.free(result);
                try decodeArray(ptr.child, result, rootParser, allocator, msg);
                return result;
            },
            .Array => |arr| {
                if (arr.len != size) {
                    // The user requested an array but the list reply from Redis
                    // contains a different amount of items.
                    var foundErr = false;
                    var i: usize = 0;
                    while (i < size) : (i += 1) {
                        // Discard all the items
                        rootParser.parse(void, msg) catch |err| switch (err) {
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
                try decodeArray(arr.child, result[0..], rootParser, allocator, msg);
                return result;
            },
            .Struct => |stc| {
                var foundNil = false;
                var foundErr = false;
                if (stc.fields.len != size) {
                    // The user requested a struct but the list reply from Redis
                    // contains a different amount of items.
                    var i: usize = 0;
                    while (i < size) : (i += 1) {
                        // Discard all the items
                        rootParser.parse(void, msg) catch |err| switch (err) {
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
                        rootParser.parse(void, msg) catch |err| switch (err) {
                            error.GotErrorReply => {
                                foundErr = true;
                            },
                            else => return err,
                        };
                    } else {
                        @field(result, field.name) = (if (@hasField(@TypeOf(allocator), "ptr"))
                            rootParser.parseAlloc(field.field_type, allocator.ptr, msg)
                        else
                            rootParser.parse(field.field_type, msg)) catch |err| switch (err) {
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
