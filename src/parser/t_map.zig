const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;
const fmt = std.fmt;
const FixBuf = @import("../types/fixbuf.zig").FixBuf;
const perfectHash = @import("../lib/perfect_hash.zig").perfectHash;

inline fn isFragmentType(comptime T: type) bool {
    const tid = @typeId(T);
    return (tid == .Struct or tid == .Enum or tid == .Union) and
        @hasDecl(T, "Redis") and @hasDecl(T.Redis, "Parser") and @hasDecl(T.Redis.Parser, "TokensPerFragment");
}

/// Parses RedisMap values.
/// Uses RESP3Parser to delegate parsing of the list contents recursively.
pub const MapParser = struct {
    pub const IsContainer = true;

    // TODO: add support for [_][2]T
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeId(T)) {
            .Struct => true,
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
            else => @compileError("Unhandled Conversion"),
            .Array => |arr| {
                if (!comptime isFragmentType(arr.child)) {
                    return error.DecodeError;
                }

                const fragNum = try std.math.divExact(usize, size, arr.child.Redis.Parser.TokensPerFragment);

                if (arr.len != fragNum) {
                    return error.LengthMismatch;
                }
                var res: T = undefined;

                for (res) |*elem| {
                    elem.* = try arr.child.Redis.Parser.parseFragment(rootParser, msg);
                }

                return res;
            },
            .Struct => |stc| {
                comptime var max_len = 0;
                comptime var fieldNames: [stc.fields.len][]const u8 = undefined;
                comptime {
                    for (stc.fields) |f, i| {
                        if (f.name.len > max_len) max_len = f.name.len;
                        fieldNames[i] = f.name;
                    }
                }
                comptime var h = perfectHash(fieldNames);

                if (stc.fields.len != size) return error.LengthMismatch;
                const Buf = FixBuf(max_len);
                var res: T = undefined;
                var i: usize = 0;
                while (i < size) : (i += 1) {
                    const b = try rootParser.parse(Buf, msg);
                    const case = h.hash(b.toSlice());
                    if (!try parseField(stc.fields, h, rootParser, &res, case, msg)) return error.UnexpectedKey;
                    // TODO: remove this workaround
                    // const found = blk: {
                    // inline for (stc.fields) |f| {
                    //     if (case == comptime h.case(f.name)) {
                    //         @field(res, f.name) = try rootParse(f.field_type, msg);
                    //         break :blk true;
                    //     }
                    // }
                    // break :blk false;
                    // };
                    // if (!found) return error.UnexpectedStructField;
                }
                return res;
            },
        }
    }

    fn parseField(comptime fields: var, comptime h: var, comptime rootParser: type, res: var, case: usize, msg: var) !bool {
        inline for (fields) |f| {
            if (case == comptime h.case(f.name)) {
                @field(res.*, f.name) = try rootParser.parse(f.field_type, msg);
                return true;
            }
        }
        return false;
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Array, .Struct => true,
            .Pointer => |ptr| isFragmentType(ptr.child) or (ptr.size == .One and @typeId(ptr.child) == .Struct),
            else => false,
        };
    }

    pub fn parseAlloc(comptime T: type, comptime rootParser: type, allocator: *std.mem.Allocator, msg: var) !T {
        switch (@typeInfo(T)) {
            else => {},
            .Pointer => |ptr| {
                // If pointer to only one element,
                // allocate it and recur.
                if (ptr.size == .One) {
                    var res = try allocator.create(ptr.child);
                    res.* = try rootParser.parseAllocFromTag(ptr.child, '%', allocator, msg);
                    return res;
                }
            },
        }
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

        // HASHMAP
        if (@typeId(T) == .Struct and @hasDecl(T, "KV")) {
            var hmap = T.init(allocator);
            var i: usize = 0;
            while (i < size) : (i += 1) {
                var key = try rootParser.parseAlloc(std.meta.fieldInfo(T.KV, "key").field_type, allocator, msg);
                var val = try rootParser.parseAlloc(std.meta.fieldInfo(T.KV, "value").field_type, allocator, msg);
                try hmap.putNoClobber(key, val);
            }
            return hmap;
        }
        // OTHER TYPES
        switch (@typeInfo(T)) {
            else => @compileError("Unsupported Conversion"),
            .Array => |arr| {
                if (!comptime isFragmentType(arr.child)) {
                    return error.DecodeError;
                }

                const fragNum = try std.math.divExact(usize, size * 2, arr.child.Redis.Parser.TokensPerFragment);

                if (arr.len != fragNum) {
                    return error.LengthMismatch;
                }
                var res: T = undefined;

                for (res) |*elem| {
                    elem.* = try arr.child.Redis.Parser.parseFragmentAlloc(rootParser, allocator, msg);
                }

                return res;
            },
            .Pointer => |ptr| {
                if (!comptime isFragmentType(ptr.child)) {
                    return error.DecodeError;
                }

                const fragNum = try std.math.divExact(usize, size * 2, ptr.child.Redis.Parser.TokensPerFragment);

                var res = try allocator.alloc(ptr.child, fragNum);
                errdefer allocator.free(res);

                for (res) |*elem| {
                    elem.* = try ptr.child.Redis.Parser.parseFragmentAlloc(rootParser, allocator, msg);
                }

                return res;
            },
            .Struct => |stc| {
                comptime var max_len = 0;
                comptime var fieldNames: [stc.fields.len][]const u8 = undefined;
                comptime {
                    for (stc.fields) |f, i| {
                        if (f.name.len > max_len) max_len = f.name.len;
                        fieldNames[i] = f.name;
                    }
                }
                comptime var h = perfectHash(fieldNames);

                if (stc.fields.len != size) return error.LengthMismatch;
                const Buf = FixBuf(max_len);
                var res: T = undefined;
                var i: usize = 0;
                while (i < size) : (i += 1) {
                    const b = try rootParser.parse(Buf, msg);
                    const case = h.hash(b.toSlice());
                    if (!try parseFieldAlloc(stc.fields, h, rootParser, &res, case, allocator, msg)) return error.UnexpectedKey;
                    // TODO: remove this workaround
                    // const found = blk: {
                    // inline for (stc.fields) |f| {
                    //     if (case == comptime h.case(f.name)) {
                    //         @field(res, f.name) = try rootParse(f.field_type, msg);
                    //         break :blk true;
                    //     }
                    // }
                    // break :blk false;
                    // };
                    // if (!found) return error.UnexpectedStructField;
                }
                return res;
            },
        }
    }
    fn parseFieldAlloc(
        comptime fields: var,
        comptime h: var,
        comptime rootParser: type,
        res: var,
        case: usize,
        allocator: *std.mem.Allocator,
        msg: var,
    ) !bool {
        inline for (fields) |f| {
            if (case == comptime h.case(f.name)) {
                @field(res.*, f.name) = try rootParser.parseAlloc(f.field_type, allocator, msg);
                return true;
            }
        }
        return false;
    }
};
