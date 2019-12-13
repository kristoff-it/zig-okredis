const std = @import("std");
const serializer = @import("./serializer.zig").CommandSerializer;

/// All the commands that operate on string keys.
pub const strings = struct {
    pub const utils = struct {
        pub const Value = @import("./commands/utils/common.zig").Value;
    };

    pub const APPEND = @import("./commands/strings_append.zig").APPEND;
    pub const BITCOUNT = @import("./commands/strings_bitcount.zig").BITCOUNT;
    pub const BITFIELD = @import("./commands/strings_bitfield.zig").BITFIELD;
    pub const BITOP = @import("./commands/strings_bitop.zig").BITOP;
    pub const BITPOS = @import("./commands/strings_bitpos.zig").BITPOS;
    pub const DECR = @import("./commands/strings_decr.zig").DECR;
    pub const DECRBY = @import("./commands/strings_decrby.zig").DECRBY;
    pub const GET = @import("./commands/strings_get.zig").GET;
    pub const GETBIT = @import("./commands/strings_getbit.zig").GETBIT;
    pub const GETRANGE = @import("./commands/strings_getrange.zig").GETRANGE;
    pub const GETSET = @import("./commands/strings_getset.zig").GETSET;
    pub const INCR = @import("./commands/strings_incr.zig").INCR;
    pub const INCRBY = @import("./commands/strings_incrby.zig").INCRBY;
    pub const INCRBYFLOAT = @import("./commands/strings_incrbyfloat.zig").INCRBYFLOAT;
    pub const MGET = @import("./commands/strings_mget.zig").MGET;
    pub const MSET = @import("./commands/strings_mset.zig").MSET;
    pub const MSETNX = @import("./commands/strings_msetnx.zig").MSETNX;
    pub const PSETEX = @import("./commands/strings_psetex.zig").PSETEX;
    pub const SET = @import("./commands/strings_set.zig").SET;
    pub const SETBIT = @import("./commands/strings_setbit.zig").SETBIT;
};

/// All the commands that operate on stream keys.
pub const streams = struct {
    pub const utils = struct {
        pub const FV = @import("./commands/utils/common.zig").FV;
    };
    pub const XADD = @import("./commands/streams_xadd.zig").XADD;
    pub const XREAD = @import("./commands/streams_xread.zig").XREAD;
    pub const XTRIM = @import("./commands/streams_xtrim.zig").XTRIM;
};

/// All the commands that operate on hash keys.
pub const hashes = struct {
    pub const utils = struct {
        pub const FV = @import("./commands/utils/common.zig").FV;
    };
    pub const HMGET = @import("./commands/hashes_hmget.zig").HMGET;
    pub const HSET = @import("./commands/hashes_hset.zig").HSET;
};

test "strings" {
    _ = @import("./commands/utils/common.zig");
    _ = @import("./commands/strings_append.zig");
    _ = @import("./commands/strings_bitcount.zig");
    _ = @import("./commands/strings_bitfield.zig");
    _ = @import("./commands/strings_bitop.zig");
    _ = @import("./commands/strings_bitpos.zig");
    _ = @import("./commands/strings_decr.zig");
    _ = @import("./commands/strings_decrby.zig");
    _ = @import("./commands/strings_get.zig");
    _ = @import("./commands/strings_getbit.zig");
    _ = @import("./commands/strings_getrange.zig");
    _ = @import("./commands/strings_getset.zig");
    _ = @import("./commands/strings_incr.zig");
    _ = @import("./commands/strings_incrby.zig");
    _ = @import("./commands/strings_incrbyfloat.zig");
    _ = @import("./commands/strings_mget.zig");
    _ = @import("./commands/strings_mset.zig");
    _ = @import("./commands/strings_msetnx.zig");
    _ = @import("./commands/strings_psetex.zig");
    _ = @import("./commands/strings_set.zig");
    _ = @import("./commands/strings_setbit.zig");

    // utils
    _ = strings.utils.Value.fromVar("hello");

    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.SliceOutStream.init(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.SliceOutStream.init(testBuf[0..]);

    // APPEND
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            strings.APPEND.init("mykey", "42"),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "APPEND", "mykey", "42" },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // BITCOUNT
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            strings.BITCOUNT.init("mykey", strings.BITCOUNT.Bounds{ .Slice = .{ .start = 1, .end = 10 } }),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "BITCOUNT", "mykey", 1, 10 },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // BITOP
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            strings.BITOP.init(.AND, "mykey", &[_][]const u8{ "key1", "key2" }),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "BITOP", "AND", "mykey", "key1", "key2" },
        );
        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // BITPOS
    {
        correctMsg.reset();
        testMsg.reset();

        var cmd = strings.BITPOS.init("test", .Zero, -3, null);
        try serializer.serializeCommand(
            &testMsg.stream,
            cmd,
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "BITPOS", "test", "0", "-3" },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // GET
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            strings.GET.init("mykey"),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "GET", "mykey" },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // GETBIT
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            strings.GETBIT.init("mykey", 100),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "GETBIT", "mykey", 100 },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // GETRANGE
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            strings.GETRANGE.init("mykey", 1, 99),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "GETRANGE", "mykey", 1, 99 },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // INCR
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            strings.INCR.init("mykey"),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "INCR", "mykey" },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // INCRBY
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            strings.INCRBY.init("mykey", 42),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "INCRBY", "mykey", 42 },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // INCRBYFLOAT
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            strings.INCRBYFLOAT.init("mykey", 42.1337),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "INCRBYFLOAT", "mykey", 42.1337 },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // SET
    {
        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                &testMsg.stream,
                strings.SET.init("mykey", 42, .NoExpire, .NoConditions),
            );
            try serializer.serializeCommand(
                &correctMsg.stream,
                .{ "SET", "mykey", "42" },
            );

            std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                &testMsg.stream,
                strings.SET.init("mykey", "banana", .NoExpire, .IfNotExisting),
            );
            try serializer.serializeCommand(
                &correctMsg.stream,
                .{ "SET", "mykey", "banana", "NX" },
            );

            std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                &testMsg.stream,
                strings.SET.init("mykey", "banana", strings.SET.Expire{ .Seconds = 20 }, .IfAlreadyExisting),
            );
            try serializer.serializeCommand(
                &correctMsg.stream,
                .{ "SET", "mykey", "banana", "EX", "20", "XX" },
            );

            std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }

    // SETBIT
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            strings.SETBIT.init("mykey", 1, 99),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "SETBIT", "mykey", 1, 99 },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}

test "streams" {
    _ = @import("./commands/streams_xadd.zig");
    _ = @import("./commands/streams_xread.zig");
    _ = @import("./commands/streams_xtrim.zig");
}

test "streams" {
    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.SliceOutStream.init(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.SliceOutStream.init(testBuf[0..]);

    // XADD
    {
        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                &testMsg.stream,
                streams.XADD.init("k1", "1-1", .NoMaxLen, &[_]streams.utils.FV{.{ .field = "f1", .value = "v1" }}),
            );
            try serializer.serializeCommand(
                &correctMsg.stream,
                .{ "XADD", "k1", "1-1", "f1", "v1" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            // std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            const MyStruct = struct {
                field1: []const u8,
                field2: u8,
                field3: usize,
            };

            const MyXADD = streams.XADD.forStruct(MyStruct);

            try serializer.serializeCommand(
                &testMsg.stream,
                MyXADD.init("k1", "1-1", .NoMaxLen, .{ .field1 = "nice!", .field2 = 'a', .field3 = 42 }),
            );
            try serializer.serializeCommand(
                &correctMsg.stream,
                .{ "XADD", "k1", "1-1", "field1", "nice!", "field2", 'a', "field3", 42 },
            );

            std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            const MyStruct = struct {
                field1: []const u8,
                field2: u8,
                field3: usize,
            };

            const MyXADD = streams.XADD.forStruct(MyStruct);

            try serializer.serializeCommand(
                &testMsg.stream,
                MyXADD.init(
                    "k1",
                    "1-1",
                    streams.XADD.MaxLen{ .PreciseMaxLen = 40 },
                    .{ .field1 = "nice!", .field2 = 'a', .field3 = 42 },
                ),
            );
            try serializer.serializeCommand(
                &correctMsg.stream,
                .{ "XADD", "k1", "1-1", "MAXLEN", 40, "field1", "nice!", "field2", 'a', "field3", 42 },
            );

            std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }

    // XREAD
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            streams.XREAD.init(
                .NoCount,
                .NoBlock,
                &[_][]const u8{ "key1", "key2" },
                &[_][]const u8{ "$", "$" },
            ),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "XREAD", "STREAMS", "key1", "key2", "$", "$" },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }

    // XTRIM
    {
        correctMsg.reset();
        testMsg.reset();

        try serializer.serializeCommand(
            &testMsg.stream,
            streams.XTRIM.init("mykey", streams.XTRIM.Strategy{ .MaxLen = .{ .count = 30 } }),
        );
        try serializer.serializeCommand(
            &correctMsg.stream,
            .{ "XTRIM", "mykey", "MAXLEN", "~", 30 },
        );

        std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
    }
}

test "hashes" {
    _ = @import("./commands/hashes_hmget.zig");
    _ = @import("./commands/hashes_hset.zig");
}

test "hashes" {
    var correctBuf: [1000]u8 = undefined;
    var correctMsg = std.io.SliceOutStream.init(correctBuf[0..]);

    var testBuf: [1000]u8 = undefined;
    var testMsg = std.io.SliceOutStream.init(testBuf[0..]);

    // HMGET
    {
        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                &testMsg.stream,
                hashes.HMGET.init("k1", &[_][]const u8{"f1"}),
            );
            try serializer.serializeCommand(
                &correctMsg.stream,
                .{ "HMGET", "k1", "f1" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            const MyStruct = struct {
                field1: []const u8,
                field2: u8,
                field3: usize,
            };

            const MyHMGET = hashes.HMGET.forStruct(MyStruct);

            try serializer.serializeCommand(
                &testMsg.stream,
                MyHMGET.init("k1"),
            );
            try serializer.serializeCommand(
                &correctMsg.stream,
                .{ "HMGET", "k1", "field1", "field2", "field3" },
            );

            std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }

    // HSET
    {
        {
            correctMsg.reset();
            testMsg.reset();

            try serializer.serializeCommand(
                &testMsg.stream,
                hashes.HSET.init("k1", &[_]hashes.utils.FV{.{ .field = "f1", .value = "v1" }}),
            );
            try serializer.serializeCommand(
                &correctMsg.stream,
                .{ "HSET", "k1", "f1", "v1" },
            );

            // std.debug.warn("{}\n\n\n{}\n", .{ correctMsg.getWritten(), testMsg.getWritten() });
            std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }

        {
            correctMsg.reset();
            testMsg.reset();

            const MyStruct = struct {
                field1: []const u8,
                field2: u8,
                field3: usize,
            };

            const MyHSET = hashes.HSET.forStruct(MyStruct);

            try serializer.serializeCommand(
                &testMsg.stream,
                MyHSET.init(
                    "k1",
                    .{ .field1 = "nice!", .field2 = 'a', .field3 = 42 },
                ),
            );
            try serializer.serializeCommand(
                &correctMsg.stream,
                .{ "HSET", "k1", "field1", "nice!", "field2", 'a', "field3", 42 },
            );

            std.testing.expectEqualSlices(u8, correctMsg.getWritten(), testMsg.getWritten());
        }
    }
}
