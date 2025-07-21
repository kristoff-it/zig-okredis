const std = @import("std");
const Reader = std.Io.Reader;
const testing = std.testing;
const fmt = std.fmt;
const builtin = @import("builtin");

const FixBuf = @import("../types/fixbuf.zig").FixBuf;

// // TODO: decide what tho do with this weird trait.
// inline fn isFragmentType(comptime T: type) bool {
//     const tid = @typeInfo(T);
//     return (tid == .@"struct" or tid == .@"enum" or tid == .@"union") and
//         @hasDecl(T, "Redis") and @hasDecl(T.Redis, "Parser") and @hasDecl(T.Redis.Parser, "TokensPerFragment");
// }

pub const MapParser = struct {
    // Understanding if we want to support a given type is more complex
    // than with other parsers as this is the only parser where we have
    // to care about the container layout (at the "toplevel") and also
    // the layout of each field-value pair.
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .array => |arr| switch (@typeInfo(arr.child)) {
                .array => |child| child.len == 2,
                // .@"struct", .@"union" => isFVType(), TODO
                else => false,
            },
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
            .pointer => |ptr| switch (@typeInfo(ptr.child)) {
                .pointer => false, // TODO: decide if we want to support it or not.
                .array => |child| child.len == 2,
                else => false,
            },
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

    pub fn parseImpl(
        comptime T: type,
        comptime rootParser: type,
        allocator: anytype,
        r: *Reader,
    ) !T {
        const digits = try r.takeSentinel('\r');
        const size = try fmt.parseInt(usize, digits, 10);
        try r.discardAll(1);

        // TODO: remove some redundant code

        // HASHMAP
        if (@hasField(@TypeOf(allocator), "ptr")) {
            if (@typeInfo(T) == .@"struct" and @hasDecl(T, "Entry")) {
                const isManaged = @hasField(T, "unmanaged");
                var hmap = if (isManaged) T.init(allocator.ptr) else T{};
                errdefer {
                    if (isManaged) {
                        hmap.deinit();
                    } else {
                        hmap.deinit(allocator.ptr);
                    }
                }

                var foundNil = false;
                var foundErr = false;
                var hashMapError = false;

                var i: usize = 0;
                while (i < size) : (i += 1) {
                    if (foundErr or foundNil) {
                        // field
                        rootParser.parse(void, r) catch |err| switch (err) {
                            error.GotErrorReply => {
                                foundErr = true;
                            },
                            else => return err,
                        };

                        // value
                        rootParser.parse(void, r) catch |err| switch (err) {
                            error.GotErrorReply => {
                                foundErr = true;
                            },
                            else => return err,
                        };
                    } else {
                        // Differently from the Lists case, here we can't `continue` immediately on fail
                        // because then we would lose count of how many tokens we consumed.
                        const key = rootParser.parseAlloc(
                            std.meta.fieldInfo(T.Entry, .key_ptr).type,
                            allocator.ptr,
                            r,
                        ) catch |err| switch (err) {
                            error.GotNilReply => blk: {
                                foundNil = true;
                                break :blk undefined;
                            },
                            error.GotErrorReply => blk: {
                                foundErr = true;
                                break :blk undefined;
                            },
                            else => return err,
                        };
                        const val = rootParser.parseAlloc(
                            std.meta.fieldInfo(T.Entry, .value_ptr).type,
                            allocator.ptr,
                            r,
                        ) catch |err| switch (err) {
                            error.GotNilReply => blk: {
                                foundNil = true;
                                break :blk undefined;
                            },
                            error.GotErrorReply => blk: {
                                foundErr = true;
                                break :blk undefined;
                            },
                            else => return err,
                        };

                        if (!foundErr and !foundNil) {
                            (if (isManaged) hmap.put(key.*, val.*) else hmap.put(
                                allocator.ptr,
                                key.*,
                                val.*,
                            )) catch {
                                hashMapError = true;
                                continue;
                            };
                        }
                    }
                }

                // Error takes precedence over Nil
                if (foundErr) return error.GotErrorReply;
                if (foundNil) return error.GotNilReply;
                if (hashMapError) return error.DecodeError; // TODO: find a way to save and return the precise error?
                return hmap;
            }
        }

        switch (@typeInfo(T)) {
            else => unreachable,
            .@"struct" => |stc| {
                var foundNil = false;
                var foundErr = false;
                if (stc.fields.len != size) {
                    // The user requested a struct but the list reply from Redis
                    // contains a different number of field-value pairs.
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

                // At comptime we create an array of strings corresponding
                // to this struct's field names.
                // This will be later used to match the hashmap's structure
                // with the struct itself.
                // TODO: implement a radix tree or something that makes this
                //       not stupidly inefficient.
                comptime var max_len = 0;
                comptime var fieldNames: [stc.fields.len][]const u8 = undefined;
                comptime {
                    for (stc.fields, 0..) |f, i| {
                        if (f.name.len > max_len) max_len = f.name.len;
                        fieldNames[i] = f.name;
                    }
                }

                const Buf = FixBuf(max_len);
                var result: T = undefined;
                // Iterating over `stc.fields.len` vs `size` is the same,
                // as the two numbers must coincide to be able to reach this
                // part of the code, but the number of struct fields has the
                // advantage of being a comptime-known number, allowing the
                // compiler to unroll the while loop, if advantageous to do so.
                var i: usize = 0;
                // upper: (renable label when fixed in Zig)
                while (i < stc.fields.len) : (i += 1) {
                    if (foundNil or foundErr) {
                        // field
                        rootParser.parse(void, r) catch |err| switch (err) {
                            error.GotErrorReply => {
                                foundErr = true;
                            },
                            else => return err,
                        };

                        // value
                        rootParser.parse(void, r) catch |err| switch (err) {
                            error.GotErrorReply => {
                                foundErr = true;
                            },
                            else => return err,
                        };
                    } else {
                        const hash_field = rootParser.parse(Buf, r) catch |err| switch (err) {
                            error.GotNilReply => blk: {
                                foundNil = true;
                                break :blk undefined;
                            },
                            error.GotErrorReply => blk: {
                                foundErr = true;
                                break :blk undefined;
                            },
                            else => return err,
                        };

                        inline for (stc.fields) |f| {
                            if (std.mem.eql(u8, f.name, hash_field.toSlice())) {
                                @field(result, f.name) = (if (@hasField(
                                    @TypeOf(allocator),
                                    "ptr",
                                ))
                                    rootParser.parseAlloc(f.type, allocator.ptr, r)
                                else
                                    rootParser.parse(f.type, r)) catch |err| switch (err) {
                                    error.GotNilReply => blk: {
                                        foundNil = true;
                                        break :blk undefined;
                                    },
                                    error.GotErrorReply => blk: {
                                        foundErr = true;
                                        break :blk undefined;
                                    },
                                    else => return err,
                                };
                                // TODO: re-enable when fixed in zig
                                // continue :upper; // only for performance reasons, it's a poor man's "else"
                            }
                        }
                    }
                }

                if (foundErr) return error.GotErrorReply;
                if (foundNil) return error.GotNilReply;
                return result;
            },
            .array => |arr| {
                if (arr.len != size) {
                    // The user requested an array but the map reply from Redis
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
                }

                // Given what we declared in isSupported,
                // we know the array has a child type of [2]X.
                var foundNil = false;
                var foundErr = false;
                const result: T = undefined;
                for (result) |*couple| {
                    if (@hasField(@TypeOf(allocator), "ptr")) {
                        couple[0] = rootParser.parseAlloc(@TypeOf(couple[0]), allocator.ptr, r) catch |err| switch (err) {
                            error.GotNilReply => blk: {
                                foundNil = true;
                                break :blk undefined;
                            },
                            error.GotErrorReply => blk: {
                                foundErr = true;
                                break :blk undefined;
                            },
                            else => return err,
                        };
                        couple[1] = rootParser.parseAlloc(@TypeOf(couple[0]), allocator.ptr, r) catch |err| switch (err) {
                            error.GotNilReply => blk: {
                                foundNil = true;
                                break :blk undefined;
                            },
                            error.GotErrorReply => blk: {
                                foundErr = true;
                                break :blk undefined;
                            },
                            else => return err,
                        };
                    } else {
                        couple[0] = try rootParser.parse(@TypeOf(couple[0]), allocator.ptr, r) catch |err| switch (err) {
                            error.GotNilReply => blk: {
                                foundNil = true;
                                break :blk undefined;
                            },
                            error.GotErrorReply => blk: {
                                foundErr = true;
                                break :blk undefined;
                            },
                            else => return err,
                        };
                        couple[1] = try rootParser.parse(@TypeOf(couple[0]), allocator.ptr, r) catch |err| switch (err) {
                            error.GotNilReply => blk: {
                                foundNil = true;
                                break :blk undefined;
                            },
                            error.GotErrorReply => blk: {
                                foundErr = true;
                                break :blk undefined;
                            },
                            else => return err,
                        };
                    }
                }

                // Error takes precedence over Nil
                if (foundErr) return error.GotErrorReply;
                if (foundNil) return error.GotNilReply;
                return result;
            },
            .pointer => |ptr| {
                if (!@hasField(@TypeOf(allocator), "ptr")) {
                    @compileError("To decode a slice you need to use sendAlloc / pipeAlloc / transAlloc!");
                }

                // Given what we declared in isSupportedAlloc,
                // we know the array has a child type of [2]X.
                var foundNil = false;
                var foundErr = false;
                const result = try allocator.ptr.alloc(ptr.child, size); // TODO: recover from OOM?
                errdefer allocator.ptr.free(result);

                for (result) |*couple| {
                    couple[0] = rootParser.parseAlloc(@TypeOf(couple[0]), allocator.ptr, r) catch |err| switch (err) {
                        error.GotNilReply => blk: {
                            foundNil = true;
                            break :blk undefined;
                        },
                        error.GotErrorReply => blk: {
                            foundErr = true;
                            break :blk undefined;
                        },
                        else => return err,
                    };
                    couple[1] = rootParser.parseAlloc(@TypeOf(couple[0]), allocator.ptr, r) catch |err| switch (err) {
                        error.GotNilReply => blk: {
                            foundNil = true;
                            break :blk undefined;
                        },
                        error.GotErrorReply => blk: {
                            foundErr = true;
                            break :blk undefined;
                        },
                        else => return err,
                    };
                }

                // Error takes precedence over Nil
                if (foundErr) return error.GotErrorReply;
                if (foundNil) return error.GotNilReply;
                return result;
            },
        }
    }

    fn decodeMap(
        comptime T: type,
        result: [][2]T,
        rootParser: anytype,
        allocator: anytype,
        r: *Reader,
    ) !void {
        var foundNil = false;
        var foundErr = false;
        for (result) |*pair| {
            if (foundNil or foundErr) {
                // field
                rootParser.parse(void, r) catch |err| switch (err) {
                    error.GotErrorReply => {
                        foundErr = true;
                    },
                    else => return err,
                };

                // value
                rootParser.parse(void, r) catch |err| switch (err) {
                    error.GotErrorReply => {
                        foundErr = true;
                    },
                    else => return err,
                };
            } else {
                pair.*[0] = (if (@hasField(@TypeOf(allocator), "ptr"))
                    rootParser.parseAlloc(T, allocator.ptr, r)
                else
                    rootParser.parse(T, r)) catch |err| switch (err) {
                    error.GotNilReply => blk: {
                        foundNil = true;
                        break :blk undefined;
                    },
                    error.GotErrorReply => blk: {
                        foundErr = true;
                        break :blk undefined;
                    },
                    else => return err,
                };

                pair.*[1] = (if (@hasField(@TypeOf(allocator), "ptr"))
                    rootParser.parseAlloc(T, allocator.ptr, r)
                else
                    rootParser.parse(T, r)) catch |err| switch (err) {
                    error.GotNilReply => blk: {
                        foundNil = true;
                        break :blk undefined;
                    },
                    error.GotErrorReply => blk: {
                        foundErr = true;
                        break :blk undefined;
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
};
