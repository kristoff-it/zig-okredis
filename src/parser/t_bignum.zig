const std = @import("std");
const testing = std.testing;

/// Parses RedisNumber values
pub const BigNumParser = struct {
    pub fn isSupported(comptime _: type) bool {
        return false;
    }

    pub fn parse(comptime T: type, comptime _: type, msg: anytype) !T {
        _ = msg;

        @compileError("The BigNum parser handles a type that needs an allocator.");
    }

    // TODO: add support for strings
    pub fn isSupportedAlloc(comptime T: type) bool {
        return T == std.math.big.int.Managed or T == []u8;
    }

    pub fn parseAlloc(comptime T: type, comptime _: type, allocator: std.mem.Allocator, msg: anytype) !T {
        // TODO: find a better max_size limit than a random 1k value
        const bigSlice = try msg.readUntilDelimiterAlloc(allocator, '\r', 1000);
        errdefer allocator.free(bigSlice);

        // Skip the remaining `\n`
        try msg.skipBytes(1, .{});

        if (T == []u8) {
            return bigSlice;
        }

        // T has to be `std.math.big.Int`
        var res: T = try T.init(allocator);
        try res.setString(10, bigSlice);
        allocator.free(bigSlice);
        return res;
    }
};

test "bignum" {
    const allocator = std.heap.page_allocator;
    var bgn = try BigNumParser.parseAlloc(std.math.big.int.Managed, void, allocator, MakeBigNum().reader());
    defer bgn.deinit();

    const bgnStr = try bgn.toString(allocator, 10, .lower);
    defer allocator.free(bgnStr);
    try testing.expectEqualSlices(u8, "1234567899990000009999876543211234567890", bgnStr);

    const str = try BigNumParser.parseAlloc([]u8, void, allocator, MakeBigNum().reader());
    defer allocator.free(str);

    try testing.expectEqualSlices(u8, bgnStr, str);
}

fn MakeBigNum() std.io.FixedBufferStream([]const u8) {
    return std.io.fixedBufferStream("(1234567899990000009999876543211234567890\r\n"[1..]);
}
