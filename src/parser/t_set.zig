const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;

/// Parses Redis Set values.
pub const SetParser = struct {
    // TODO: prevent users from unmarshaling structs out of strings
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Array => true,
            else => false,
        };
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        // HashMap
        if (@typeInfo(T) == .Struct and @hasDecl(T, "Entry")) {
            return void == std.meta.fieldInfo(T.Entry, .value_ptr).field_type;
        }

        return switch (@typeInfo(T)) {
            .Pointer => true,
            else => isSupported(T),
        };
    }

    pub fn parse(comptime T: type, comptime rootParser: type, msg: anytype) !T {
        return parseImpl(T, rootParser, .{}, msg);
    }

    pub fn parseAlloc(comptime T: type, comptime rootParser: type, allocator: std.mem.Allocator, msg: anytype) !T {
        // HASHMAP
        if (@typeInfo(T) == .Struct and @hasDecl(T, "Entry")) {
            const isManaged = @typeInfo(@TypeOf(T.deinit)).Fn.args.len == 1;

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

            var hmap = T.init(allocator);
            errdefer {
                if (isManaged) {
                    hmap.deinit();
                } else {
                    hmap.deinit(allocator.ptr);
                }
            }

            const KeyType = std.meta.fieldInfo(T.Entry, .key_ptr).field_type;

            var foundNil = false;
            var foundErr = false;
            var hashMapError = false;
            var i: usize = 0;
            while (i < size) : (i += 1) {
                if (foundNil or foundErr or hashMapError) {
                    rootParser.parse(void, msg) catch |err| switch (err) {
                        error.GotErrorReply => {
                            foundErr = true;
                        },
                        else => return err,
                    };
                } else {
                    var key = rootParser.parseAlloc(KeyType, allocator, msg) catch |err| switch (err) {
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

                    // If we got here then no error occurred and we can add the key.
                    (if (isManaged) hmap.put(key.*, {}) else hmap.put(allocator.ptr, key.*, {})) catch {
                        hashMapError = true;
                        continue;
                    };
                }
            }

            if (foundErr) return error.GotErrorReply;
            if (foundNil) return error.GotNilReply;
            if (hashMapError) return error.DecodeError; // TODO: find a way to save and return the precise error?
            return hmap;
        }

        return parseImpl(T, rootParser, .{ .ptr = allocator }, msg);
    }

    pub fn parseImpl(comptime T: type, comptime rootParser: type, allocator: anytype, msg: anytype) !T {
        // Indirectly delegate all cases to the list parser.

        // TODO: fix this. Delegating with the same top-level T looks
        // like a loop to the compiler. Solution would be to make the
        // tag comptime known.
        //
        // return if (@hasField(@TypeOf(allocator), "ptr"))
        //     rootParser.parseAllocFromTag(T, '*', allocator.ptr, msg)
        // else
        //     rootParser.parseFromTag(T, '*', msg);
        const ListParser = @import("./t_list.zig").ListParser;
        return if (@hasField(@TypeOf(allocator), "ptr"))
            ListParser.parseAlloc(T, rootParser, allocator.ptr, msg)
        else
            ListParser.parse(T, rootParser, msg);
        // return error.DecodeError;
    }
};

test "set" {
    const parser = @import("../parser.zig").RESP3Parser;
    const allocator = std.heap.page_allocator;

    const arr = try SetParser.parse([3]i32, parser, MakeSet().reader());
    try testing.expectEqualSlices(i32, &[3]i32{ 1, 2, 3 }, &arr);

    const sli = try SetParser.parseAlloc([]i64, parser, allocator, MakeSet().reader());
    defer allocator.free(sli);
    try testing.expectEqualSlices(i64, &[3]i64{ 1, 2, 3 }, sli);

    var hmap = try SetParser.parseAlloc(std.AutoHashMap(i64, void), parser, allocator, MakeSet().reader());
    defer hmap.deinit();

    if (hmap.remove(1)) {} else unreachable;
    if (hmap.remove(2)) {} else unreachable;
    if (hmap.remove(3)) {} else unreachable;

    try testing.expectEqual(@as(usize, 0), hmap.count());
}

fn MakeSet() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("~3\r\n:1\r\n:2\r\n:3\r\n"[1..]);
}
