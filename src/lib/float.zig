///
/// A simple and very fast float parser in Zig.
///
/// Written by Tetralux@teknik.io, 2019-09-06.
///
///
/// Will error if you have too many decimal places,
/// invalid characters within the number, or an
/// empty string.
///
/// Is also subject to rounding errors.
///
const std = @import("std");
const mem = std.mem;
const time = std.time;
const math = std.math;

const inf = math.inf;
const nan = math.nan;
const warn = std.debug.warn;

fn toDigit(ch: u8) callconv(.Inline) !u8 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    return error.InvalidCharacter;
}

fn parseFloat(comptime T: type, slice: []const u8) error{ Empty, InvalidCharacter, TooManyDigits }!T {
    var s = mem.separate(slice, " ").next() orelse return error.Empty;
    if (s.len == 0) return error.Empty;

    var is_neg = s[0] == '-';
    if (is_neg) {
        if (s.len == 1) return error.Empty;
        s = s[1..];
    }

    if (mem.eql(u8, s[0..3], "inf")) return if (is_neg) -inf(T) else inf(T);
    if (mem.eql(u8, s[0..3], "nan")) return nan(T); // -nan makes no sense.

    // Read the digits into an integer and note
    // where the decimal point is.
    var n: u64 = 0;
    var decimal_point_index: isize = -1;
    var decimal_places: usize = 0;
    var numeral_places: usize = 0;
    for (s) |ch, i| {
        if (ch == '.') {
            decimal_point_index = @intCast(isize, i);
            continue;
        }
        if (decimal_point_index == -1)
            numeral_places += 1
        else
            decimal_places += 1;
        n += try toDigit(ch);
        n *= 10;
    }
    if (decimal_places + numeral_places > 18) return error.TooManyDigits; // f64 has 18 s.f.

    // Shift the decimal point into the right place.
    var n_as_float = @intToFloat(f64, n) / 10;

    if (decimal_point_index != -1) {
        // We counted from the front, we'll insert the decimal point from the back.
        const decimal_point_index_from_back = @intCast(isize, s.len) - decimal_point_index - 1;

        {
            var i: isize = 0;
            while (i < decimal_point_index_from_back) : (i += 1) {
                n_as_float /= 10;
            }
        }
    }

    var res = @floatCast(T, n_as_float);
    if (is_neg) res *= -1;
    return res;
}

pub fn main() !void {
    {
        var total: u64 = 0;
        const its = 10240000;
        var i: u64 = 0;
        while (i < its) : (i += 1) {
            var t = try time.Timer.start();
            var f = try parseFloat(f64, "4.77777777777777777");
            var took = t.read();
            // warn("f is {d}\n", f);
            // break;
            total += took;
        }
        warn("average time: {d} ns\n", @intToFloat(f64, total) / @intToFloat(f64, its));
    }

    {
        var total: u64 = 0;
        const its = 10240000;
        var i: u64 = 0;
        while (i < its) : (i += 1) {
            var t = try time.Timer.start();
            var f = try std.fmt.parseFloat(f64, "4.77777777777777778");
            var took = t.read();
            total += took;
        }
        warn("average time: {d} ns\n", @intToFloat(f64, total) / @intToFloat(f64, its));
    }
}
