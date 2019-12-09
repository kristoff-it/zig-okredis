const std = @import("std");
const traits = @import("./traits.zig");

pub const CommandSerializer = struct {
    pub fn serializeCommand(msg: var, command: var) !void {
        // Serializes an entire command.
        // Callers can expect this function to:
        // 1. Write the number of arguments in the command
        //    (optionally using the Redis.Arguments trait)
        // 2. Write each argument
        //    (optionally using the Redis.Arguments trait)
        //
        // `command` can be:
        // 1. Redis.Command trait
        // 2. Redis.Arguments trait
        // 3. ArgList
        // 4. Array / Slice
        //
        // Redis.Command types can call this function
        // in order to delegate simple serialization
        // scenarios, the only requirement being that they
        // pass an ArgList or an Array/Slice, and not another
        // reference to themselves (as that would loop forever).
        //
        // As an example, the `commands.GET` command calls this
        // function passing `.{"GET", self.key}` as
        // argument.
        const CmdT = @typeOf(command);
        if (comptime traits.isCommand(CmdT)) {
            return CmdT.Redis.Command.serialize(command, CommandSerializer, msg);
        }

        // TODO: decide if this should be removed.
        // Why would someone use Arguments directly?
        if (comptime traits.isArguments(CmdT)) {
            try msg.print("*{}\r\n", CmdT.Redis.Arguments.count(command));
            return CmdT.Redis.Arguments.serialize(command, CommandSerializer, msg);
        }

        switch (@typeInfo(CmdT)) {
            else => {
                @compileLog(CmdT);
                @compileError("unsupported");
            },
            .Struct => {
                // Count the number of arguments
                var argNum: usize = 0;
                inline for (std.meta.fields(CmdT)) |field| {
                    const arg = @field(command, field.name);
                    const ArgT = @typeOf(arg);
                    if (comptime traits.isArguments(ArgT)) {
                        argNum += ArgT.Redis.Arguments.count(arg);
                    } else {
                        argNum += 1;
                    }
                }

                // Write the number of arguments
                // std.debug.warn("*{}\r\n", argNum);
                try msg.print("*{}\r\n", argNum);

                // Serialize each argument
                inline for (std.meta.fields(CmdT)) |field| {
                    const arg = @field(command, field.name);
                    const ArgT = @typeOf(arg);
                    if (comptime traits.isArguments(ArgT)) {
                        try ArgT.Redis.Arguments.serialize(arg, CommandSerializer, msg);
                    } else {
                        try serializeArgument(msg, ArgT, arg);
                    }
                }
            },
        }
    }

    pub fn serializeArgument(msg: var, comptime T: type, val: T) !void {
        // Serializes a single argument.
        // Supports the following types:
        // 1. Strings
        // 2. Numbers
        //
        // Redis.Argument types can use this function
        // in their implementation.
        // Similarly to what happens with Redis.Command types
        // and serializeCommand(), Redis.Argument types
        // can call this function and pass a basic type.
        switch (@typeInfo(T)) {
            .Int, .Float, .ComptimeInt, .ComptimeFloat => {
                // TODO: write a better method
                var buf: [100]u8 = undefined;
                var res = try std.fmt.bufPrint(buf[0..], "{}", val);
                // std.debug.warn("${}\r\n{s}\r\n", res.len, res);
                try msg.print("${}\r\n{s}\r\n", res.len, res);
            },
            .Array => {
                // std.debug.warn("${}\r\n{s}\r\n", val.len, val);
                try msg.print("${}\r\n{s}\r\n", val.len, val);
            },
            .Pointer => |ptr| {
                switch (ptr.size) {
                    .One => {
                        switch (@typeInfo(ptr.child)) {
                            .Array => {
                                const arr = val.*;
                                try msg.print("${}\r\n{s}\r\n", arr.len, arr);
                                return;
                            },
                            else => @compileError("unsupported"),
                        }
                    },
                    .Slice => {
                        try msg.print("${}\r\n{s}\r\n", val.len, val);
                    },
                    else => {
                        if ((ptr.size != .Slice or ptr.size != .One) or ptr.child != u8) {
                            @compileLog(ptr.size);
                            @compileLog(ptr.child);
                            @compileError("Unsupported type.");
                        }
                        std.debug.warn("${}\r\n{s}\r\n", val.len, val);
                    },
                }
            },
            else => @compileError("Unsupported type."),
        }
    }
};
