const std = @import("std");

pub const StreamFns = enum {
    XADD,
    XREAD,
    XREADGROUP,
    XRANGE,
    XREVRANGE,
};

pub const SpecialIDs = struct {
    pub const NEW_MESSAGES = "$";
    pub const ASSIGN_NEW_MESSAGES = "<";
    pub const MIN = "-";
    pub const MAX = "+";
    pub const AUTO_ID = "*";
    pub const BEGINNING = "0-0";
};

pub fn isValidStreamID(cmd: StreamFns, id: []const u8) bool {
    return switch (cmd) {
        .XREAD => isNumericStreamID(id) or isAny(id, .{SpecialIDs.NEW_MESSAGES}),
        .XREADGROUP => isNumericStreamID(id) or isAny(id, .{ SpecialIDs.NEW_MESSAGES, SpecialIDs.ASSIGN_NEW_MESSAGES }),
        .XADD => !std.mem.eql(u8, id, SpecialIDs.BEGINNING) and (isNumericStreamID(id) or isAny(id, .{SpecialIDs.AUTO_ID})),
        .XRANGE, .XREVRANGE => isNumericStreamID(id) or isAny(id, .{ SpecialIDs.MIN, SpecialIDs.MAX }),
    };
}

fn isAny(arg: []const u8, strings: anytype) bool {
    inline for (std.meta.fields(@TypeOf(strings))) |field| {
        const str = @field(strings, field.name);
        if (std.mem.eql(u8, arg, str)) return true;
    }
    return false;
}

pub fn isNumericStreamID(id: []const u8) bool {
    if (id.len > 41) return false;

    var hyphenPosition: isize = -1;
    var i: usize = 0;
    while (i < id.len) : (i += 1) {
        switch (id[i]) {
            '0'...'9' => {},
            '-' => {
                if (hyphenPosition != -1) return false;
                hyphenPosition = @bitCast(isize, i);
                const first_part = id[0..i];
                if (first_part.len == 0) return false;
                _ = std.fmt.parseInt(u64, first_part, 10) catch return false;
            },
            else => return false,
        }
    }
    const second_part = id[@bitCast(usize, hyphenPosition + 1)..];
    if (second_part.len == 0) return false;
    _ = std.fmt.parseInt(u64, second_part, 10) catch return false;
    return true;
}

test "numeric stream ids" {
    try std.testing.expectEqual(false, isNumericStreamID(""));
    try std.testing.expectEqual(false, isNumericStreamID(" "));
    try std.testing.expectEqual(false, isNumericStreamID("-"));
    try std.testing.expectEqual(false, isNumericStreamID("-0"));
    try std.testing.expectEqual(false, isNumericStreamID("-1234"));
    try std.testing.expectEqual(false, isNumericStreamID("0-"));
    try std.testing.expectEqual(false, isNumericStreamID("123-"));
    try std.testing.expectEqual(true, isNumericStreamID("0"));
    try std.testing.expectEqual(true, isNumericStreamID("123"));
    try std.testing.expectEqual(true, isNumericStreamID("0-0"));
    try std.testing.expectEqual(true, isNumericStreamID("0-123"));
    try std.testing.expectEqual(true, isNumericStreamID("123123123-123123123"));
    try std.testing.expectEqual(true, isNumericStreamID("18446744073709551615-18446744073709551615"));
    try std.testing.expectEqual(false, isNumericStreamID("18446744073709551616-18446744073709551615"));
    try std.testing.expectEqual(false, isNumericStreamID("18446744073709551615-18446744073709551616"));
    try std.testing.expectEqual(false, isNumericStreamID("922337203685412312377580123123112317-922337212312312312312036854775808"));
}
