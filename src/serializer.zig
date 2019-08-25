const std = @import("std");
const traits = @import("./traits.zig");

const errorMsg = "Valid arguments are just numbers, booleans " ++
    "(which become 0 or 1) and strings (either as []u8 or as [_]u8), " ++
    "unless the type implements `Redis.ArgSerializer`.";

pub const ArgSerializer = struct {
    pub fn serialize(msg: var, vals: ...) !void {
        // Client commands start by stating the number of arguments they have.
        // Types that define their own serialization have the option of writing
        // themselves as multiple arguments. This option is given because, while
        // Redis can reply with arbitrarily complex data structures, client
        // commands must be unstructured. There are common patterns that emerge,
        // like with HMSET, where it makes sense to translate a struct to a
        // sequence of `field` `value`.
        // Types that implement the `Redis.ArgSerializer` trait must implement
        // a method that returns how many arguments a given value is going to
        // translate to, and then make sure to produce the same amount of args,
        // once ArgSerializer asks to serialize the value.
        var argNum: usize = 0;

        // Loop over arguments to obtain the number of arguments
        comptime var i = 0;
        inline while (i < vals.len) : (i += 1) {
            var val = vals[i];
            comptime var T = @typeOf(val);
            switch (@typeInfo(T)) {
                else => @compileError(errorMsg),
                .Int, .Float, .Bool => argNum += 1,
                .Array => |arr| {
                    if (arr.child != u8) @compileError(errorMsg);
                    argNum += 1;
                },
                .Union, .Enum, .Struct => {
                    argNum += if (comptime traits.isArgType(ptr.child))
                        T.Redis.ArgParse.numArgs(val.*)
                    else
                        @compileError(errorMsg);
                },
                .Pointer => |ptr| switch (ptr.size) {
                    .Many, .C => @compileError(errorMsg),
                    .One => {
                        argNum += if (comptime traits.isArgType(ptr.child))
                            T.Redis.ArgParse.numArgs(val.*)
                        else
                            1;
                    },
                    .Slice => {
                        if (arr.child != u8) @compileError(errorMsg);
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

    pub inline fn writeVal(msg: var, val: var) !void {
        const T = @typeOf(val);
        if (comptime traits.isArgType(T)) {
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
