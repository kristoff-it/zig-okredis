const std = @import("std");
const Reader = std.Io.Reader;
const fmt = std.fmt;
const testing = std.testing;

/// Parses Redis Set values.
pub const SetParser = struct {
    // TODO: prevent users from unmarshaling structs out of strings
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .array => true,
            else => false,
        };
    }

    pub fn isSupportedAlloc(comptime T: type) bool {
        // HashMap
        if (@typeInfo(T) == .@"struct" and @hasDecl(T, "Entry")) {
            return void == std.meta.fieldInfo(T.Entry, .value_ptr).type;
        }

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
        // HASHMAP
        if (@typeInfo(T) == .@"struct" and @hasDecl(T, "Entry")) {
            const isManaged = @typeInfo(@TypeOf(T.deinit)).@"fn".params.len == 1;

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

            var hmap = T.init(allocator);
            errdefer {
                if (isManaged) {
                    hmap.deinit();
                } else {
                    hmap.deinit(allocator.ptr);
                }
            }

            const KeyType = std.meta.fieldInfo(T.Entry, .key_ptr).type;

            var foundNil = false;
            var foundErr = false;
            var hashMapError = false;
            var i: usize = 0;
            while (i < size) : (i += 1) {
                if (foundNil or foundErr or hashMapError) {
                    rootParser.parse(void, r) catch |err| switch (err) {
                        error.GotErrorReply => {
                            foundErr = true;
                        },
                        else => return err,
                    };
                } else {
                    const key = rootParser.parseAlloc(KeyType, allocator, r) catch |err| switch (err) {
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

        return parseImpl(T, rootParser, .{ .ptr = allocator }, r);
    }

    pub fn parseImpl(comptime T: type, comptime rootParser: type, allocator: anytype, r: *Reader) !T {
        // Indirectly delegate all cases to the list parser.

        // TODO: fix this. Delegating with the same top-level T looks
        // like a loop to the compiler. Solution would be to make the
        // tag comptime known.
        //
        // return if (@hasField(@TypeOf(allocator), "ptr"))
        //     rootParser.parseAllocFromTag(T, '*', allocator.ptr, r)
        // else
        //     rootParser.parseFromTag(T, '*', r);
        const ListParser = @import("./t_list.zig").ListParser;
        return if (@hasField(@TypeOf(allocator), "ptr"))
            ListParser.parseAlloc(T, rootParser, allocator.ptr, r)
        else
            ListParser.parse(T, rootParser, r);
        // return error.DecodeError;
    }
};

test "set" {
    const parser = @import("../parser.zig").RESP3Parser;
    const allocator = std.heap.page_allocator;

    var set1 = MakeSet();
    const arr = try SetParser.parse([3]i32, parser, &set1);
    try testing.expectEqualSlices(i32, &[3]i32{ 1, 2, 3 }, &arr);

    var set2 = MakeSet();
    const sli = try SetParser.parseAlloc([]i64, parser, allocator, &set2);
    defer allocator.free(sli);
    try testing.expectEqualSlices(i64, &[3]i64{ 1, 2, 3 }, sli);

    var set3 = MakeSet();
    var hmap = try SetParser.parseAlloc(std.AutoHashMap(i64, void), parser, allocator, &set3);
    defer hmap.deinit();

    if (hmap.remove(1)) {} else unreachable;
    if (hmap.remove(2)) {} else unreachable;
    if (hmap.remove(3)) {} else unreachable;

    try testing.expectEqual(@as(usize, 0), hmap.count());
}

// TODO: get rid of this!
fn MakeSet() Reader {
    return std.Io.Reader.fixed("~3\r\n:1\r\n:2\r\n:3\r\n"[1..]);
}
