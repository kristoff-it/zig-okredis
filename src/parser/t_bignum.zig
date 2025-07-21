const std = @import("std");
const Reader = std.Io.Reader;
const testing = std.testing;

/// Parses RedisNumber values
pub const BigNumParser = struct {
    pub fn isSupported(comptime _: type) bool {
        return false;
    }

    pub fn parse(comptime T: type, comptime _: type, r: *Reader) !T {
        _ = r;

        @compileError("The BigNum parser handles a type that needs an allocator.");
    }

    // TODO: add support for strings
    pub fn isSupportedAlloc(comptime T: type) bool {
        return T == std.math.big.int.Managed or T == []u8;
    }

    pub fn parseAlloc(
        comptime T: type,
        comptime _: type,
        allocator: std.mem.Allocator,
        r: *Reader,
    ) !T {
        var w: std.Io.Writer.Allocating = .init(allocator);
        errdefer w.deinit();

        _ = try r.streamDelimiter(&w.writer, '\r');
        try r.discardAll(2);

        if (T == []u8 or T == []const u8) {
            return w.toOwnedSlice();
        }

        // TODO: check that the type is correct!
        // T has to be `std.math.big.int`
        var res: T = try T.init(allocator);
        try res.setString(10, try w.toOwnedSlice());
        return res;
    }
};

test "bignum" {
    const allocator = std.heap.page_allocator;
    var r_bignum = MakeBigNum();
    var bgn = try BigNumParser.parseAlloc(
        std.math.big.int.Managed,
        void,
        allocator,
        &r_bignum,
    );
    defer bgn.deinit();

    const bgnStr = try bgn.toString(allocator, 10, .lower);
    defer allocator.free(bgnStr);
    try testing.expectEqualSlices(u8, "1234567899990000009999876543211234567890", bgnStr);

    var r_bignum2 = MakeBigNum();
    const str = try BigNumParser.parseAlloc(
        []u8,
        void,
        allocator,
        &r_bignum2,
    );
    defer allocator.free(str);

    try testing.expectEqualSlices(u8, bgnStr, str);
}

// TODO: get rid of this
fn MakeBigNum() Reader {
    return std.Io.Reader.fixed(
        "(1234567899990000009999876543211234567890\r\n"[1..],
    );
}
