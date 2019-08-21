// Taken from https://andrewkelley.me/post/string-matching-comptime-perfect-hashing-zig.html
// and adapted to the new changes in Zig.

const std = @import("std");
pub fn perfectHash(comptime strs: []const []const u8) type {
    const Op = union(enum) {
        /// add the length of the string
        Length,

        /// add the byte at index % len
        Index: usize,

        /// right shift then xor with constant
        XorShiftMultiply: u32,
    };
    const S = struct {
        fn hash(comptime plan: []Op, s: []const u8) u32 {
            var h: u32 = 0;
            inline for (plan) |op| {
                switch (op) {
                    Op.Length => {
                        h +%= @truncate(u32, s.len);
                    },
                    Op.Index => |index| {
                        h +%= s[index % s.len];
                    },
                    Op.XorShiftMultiply => |x| {
                        h ^= x >> 16;
                    },
                }
            }
            return h;
        }

        fn testPlan(comptime plan: []Op) bool {
            var hit = [1]bool{false} ** strs.len;
            for (strs) |s| {
                const h = hash(plan, s);
                const i = h % hit.len;
                if (hit[i]) {
                    // hit this index twice
                    return false;
                }
                hit[i] = true;
            }
            return true;
        }
    };

    var ops_buf: [10]Op = undefined;

    const plan = have_a_plan: {
        var seed: u32 = 0x45d9f3b;
        var index_i: usize = 0;
        const try_seed_count = 50;
        const try_index_count = 50;

        @setEvalBranchQuota(50000);

        while (index_i < try_index_count) : (index_i += 1) {
            const bool_values = if (index_i == 0) [_]bool{true} else [_]bool{ false, true };
            for (bool_values) |try_length| {
                var seed_i: usize = 0;
                while (seed_i < try_seed_count) : (seed_i += 1) {
                    comptime var rand_state = std.rand.Xoroshiro128.init(seed + seed_i);
                    const rng = &rand_state.random;

                    var ops_index = 0;

                    if (try_length) {
                        ops_buf[ops_index] = Op.Length;
                        ops_index += 1;

                        if (S.testPlan(ops_buf[0..ops_index]))
                            break :have_a_plan ops_buf[0..ops_index];

                        ops_buf[ops_index] = Op{ .XorShiftMultiply = rng.scalar(u32) };
                        ops_index += 1;

                        if (S.testPlan(ops_buf[0..ops_index]))
                            break :have_a_plan ops_buf[0..ops_index];
                    }

                    ops_buf[ops_index] = Op{ .XorShiftMultiply = rng.scalar(u32) };
                    ops_index += 1;

                    if (S.testPlan(ops_buf[0..ops_index]))
                        break :have_a_plan ops_buf[0..ops_index];

                    const before_bytes_it_index = ops_index;

                    var byte_index = 0;
                    while (byte_index < index_i) : (byte_index += 1) {
                        ops_index = before_bytes_it_index;

                        ops_buf[ops_index] = Op{ .Index = rng.scalar(u32) % try_index_count };
                        ops_index += 1;

                        if (S.testPlan(ops_buf[0..ops_index]))
                            break :have_a_plan ops_buf[0..ops_index];

                        ops_buf[ops_index] = Op{ .XorShiftMultiply = rng.scalar(u32) };
                        ops_index += 1;

                        if (S.testPlan(ops_buf[0..ops_index]))
                            break :have_a_plan ops_buf[0..ops_index];
                    }
                }
            }
        }

        @compileError("unable to come up with perfect hash");
    };

    return struct {
        pub fn case(comptime s: []const u8) usize {
            inline for (strs) |str| {
                if (std.mem.eql(u8, str, s)) {
                    return hash(s);
                }
            }
            @compileError("case value '" ++ s ++ "' not declared");
        }
        pub fn hash(s: []const u8) usize {
            if (std.debug.runtime_safety) {
                const ok = for (strs) |str| {
                    if (std.mem.eql(u8, str, s))
                        break true;
                } else false;
                if (!ok) {
                    std.debug.panic("attempt to perfect hash {} which was not declared", s);
                }
            }
            return S.hash(plan, s) % strs.len;
        }
    };
}
