const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;

/// Parses Redis Set values.
pub const SetParser = struct {
    // TODO: prevent users from unmarshaling structs out of strings
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeId(T)) {
            .Array => true,
            else => false,
        };
    }

    pub fn parse(comptime T: type, comptime rootParser: type, msg: var) !T {
        // Make ListParser deal with this by lying to the rootParser.
        // return rootParser.parseFromTag(T, '*', msg);

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
                return result;
            },
            else => @compileError("Unhandled Conversion"),
        }
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        // HashMap
        if (@typeId(T) == .Struct and @hasDecl(T, "KV")) {
            return void == std.meta.fieldInfo(T.KV, "value").field_type;
        }

        return switch (@typeInfo(T)) {
            .Array, .Pointer => true,
            else => false,
        };
    }

    pub fn parseAlloc(comptime T: type, comptime rootParser: type, allocator: *std.mem.Allocator, msg: var) !T {
        // HASHMAP
        if (@typeId(T) == .Struct and @hasDecl(T, "KV")) {
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

            var hmap = T.init(allocator);
            var i: usize = 0;
            while (i < size) : (i += 1) {
                var key = try rootParser.parseAlloc(std.meta.fieldInfo(T.KV, "key").field_type, allocator, msg);
                try hmap.putNoClobber(key, {});
            }
            return hmap;
        } else {
            // return rootParser.parseAllocFromTag(T, '*', allocator, msg);
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

                    return switch (ptr.size) {
                        .One, .Many => @compileError("Only Slices and C pointers should reach sub-parsers"),
                        .Slice => res,
                        .C => @ptrCast(T, res.ptr),
                    };
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
    }
};

test "set" {
    const parser = @import("../parser.zig").RESP3Parser;
    const allocator = std.heap.direct_allocator;

    const arr = try SetParser.parse([3]i32, parser, &MakeSet().stream);
    testing.expectEqualSlices(i32, &[3]i32{ 1, 2, 3 }, &arr);

    const sli = try SetParser.parseAlloc([]i64, parser, allocator, &MakeSet().stream);
    defer allocator.free(sli);
    testing.expectEqualSlices(i64, &[3]i64{ 1, 2, 3 }, sli);

    var hmap = try SetParser.parseAlloc(std.AutoHashMap(i64, void), parser, allocator, &MakeSet().stream);
    defer hmap.deinit();

    if (hmap.remove(1)) |_| {} else unreachable;
    if (hmap.remove(2)) |_| {} else unreachable;
    if (hmap.remove(3)) |_| {} else unreachable;

    testing.expectEqual(@as(usize, 0), hmap.count());
}

fn MakeSet() std.io.SliceInStream {
    return std.io.SliceInStream.init("~3\r\n:1\r\n:2\r\n:3\r\n"[1..]);
}
