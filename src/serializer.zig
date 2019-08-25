const std = @import("std");

pub const ArgSerializer = struct {
    pub fn serialize(msg: var, vals: ...) !void {
        // We first need to write to the
        // stream how many arguments we're going to send.
        // This could be as simple as `vals.len`, but this
        // library offers two quality-of-life features:
        //    - Optionals are skipped when null
        //    - Types can define their own serialization
        // The second point is of particular interest
        // because it allows types to serialize themselves
        // to more than one command argument.
        // For this reason we need to first count to how
        // many Redis arguments `vals` is going to correspond to.
        var argNum: usize = 0;

        // Loop over arguments to obtain the number of arguments
        comptime var i = 0;
        inline while (i < vals.len) : (i += 1) {
            var val = vals[i];
            comptime var T = @typeOf(val);
            switch (@typeInfo(T)) {
                else => {
                    argNum += if (comptime isArgType(T))
                        T.Redis.ArgParse.numArgs(val)
                    else
                        1;
                },
                .Optional => |opt| {
                    if (val) |unwrapped_val| {
                        argNum += if (comptime isArgType(opt.child))
                            T.Redis.ArgParse.numArgs(val)
                        else
                            1;
                    }
                    // We do nothing otherwise, the argument is skipped.
                },
                .Pointer => |ptr| switch (ptr.size) {
                    .Many, .C => @compileError("Not supported"),
                    .One => {
                        argNum += if (comptime isArgType(ptr.child))
                            T.Redis.ArgParse.numArgs(val.*)
                        else
                            1;
                    },
                    .Slice => {
                        argNum += 1;
                    },
                },
            }
        }

        // Write the number of arguments
        try msg.print("*{}\r\n", argNum);

        // Loop again, but this time to send data to
        // the stream.
        i = 0;
        inline while (i < vals.len) : (i += 1) {
            var val = vals[i];
            comptime var T = @typeOf(val);
            switch (@typeInfo(T)) {
                else => try writeVal(msg, val),
                .Optional => |opt| {
                    if (val) |unwrapped_val| {
                        try writeVal(msg, unwrapped_val);
                    }
                    // We do nothing otherwise.
                },
                .Pointer => |ptr| switch (ptr.size) {
                    .Many, .C => @compileError("Not supported"),
                    .One => {
                        try writeVal(msg, val.*);
                    },
                    .Slice => {
                        try writeVal(msg, val);
                    },
                },
            }
        }
    }

    inline fn isArgType(comptime T: type) bool {
        const tid = @typeId(T);
        return (tid == .Struct or tid == .Enum or tid == .Union) and
            @hasDecl(T, "Redis") and @hasDecl(T.Redis, "ArgSerializer");
    }

    pub inline fn writeVal(msg: var, val: var) !void {
        const T = @typeOf(val);
        if (comptime isArgType(T)) {
            try T.Redis.ArgSerializer.serialize(msg, val);
            return;
        }

        switch (@typeInfo(@typeOf(val))) {
            else => @compileError("Unsupported conversion"),
            .Bool => {
                try msg.print("$1\r\n{}\r\n", if (val) "1" else "0");
            },
            .Int, .Float => {
                // TODO: write a better method
                var buf: [100]u8 = undefined;
                var res = try fmt.bufPrint(buf[0..], "{}", val);
                try msg.print("${}\r\n{s}\r\n", res.len, res);
            },
            .Array => try msg.print("${}\r\n{s}\r\n", val.len, val),
            .Pointer => |ptr| switch (ptr.size) {
                .Slice => try msg.print("${}\r\n{s}\r\n", val.len, val),
                .One, .C, .Many => @compileError("unsupported converison"), // TODO: consider supporting c strings
            },
        }
    }
};

test "some strings" {
    var buf: [1000]u8 = undefined;
    var out = std.io.SliceOutStream.init(buf[0..]);
    try ArgSerializer.serialize(&out.stream, "SET", "key"[0..], "42");
    std.debug.warn("--> {}\n", out.getWritten());
}
