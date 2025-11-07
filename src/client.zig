const Client = @This();
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const RESP3 = @import("./parser.zig").RESP3Parser;
const CommandSerializer = @import("./serializer.zig").CommandSerializer;
const OrErr = @import("./types/error.zig").OrErr;

pub const Auth = struct {
    user: ?[]const u8,
    pass: []const u8,
};

pub const InitOptions = struct {
    auth: ?Auth = null,
};

io: Io,
w: *Io.Writer,
r: *Io.Reader,
wl: Io.Mutex = .init,
rl: Io.Mutex = .init,
pending_tail: ?*Pending = null,
broken: bool = false,

/// Initializes a Client on a Reader and a Writer provided by the user.
pub fn init(io: Io, reader: *Io.Reader, writer: *Io.Writer, auth: ?Auth) !Client {
    var client: Client = .{ .io = io, .r = reader, .w = writer };

    if (auth) |a| {
        if (a.user) |user| {
            client.send(void, .{ "AUTH", user, a.pass }) catch |err| {
                client.broken = true;
                return err;
            };
        } else {
            client.send(void, .{ "AUTH", a.pass }) catch |err| {
                client.broken = true;
                return err;
            };
        }
    }

    const result = client.send(OrErr(void), .{ "HELLO", "3" }) catch |err| {
        client.broken = true;
        return err;
    };

    switch (result) {
        .Ok => return client,
        .Nil => unreachable,
        .Err => |err| if (std.mem.eql(u8, err.getCode(), "NOAUTH")) {
            return error.Unauthenticated;
        } else {
            return error.ServerTooOld;
        },
    }
}

pub fn close(_: Client) void {
    @compileError("deprecated, okredis.Client doesn't keep a reference to the connection anymore.");
}

/// Sends a command to Redis and tries to parse the response as the specified
/// type.
pub fn send(client: *Client, comptime T: type, cmd: anytype) !T {
    return client.pipelineImpl(T, cmd, .{ .one = {} });
}

/// Like `send`, can allocate memory.
pub fn sendAlloc(
    client: *Client,
    comptime T: type,
    allocator: Allocator,
    cmd: anytype,
) !T {
    return client.pipelineImpl(T, cmd, .{ .one = {}, .ptr = allocator });
}

/// Performs a Redis MULTI/EXEC transaction using pipelining.
/// It's mostly provided for convenience as the same result
/// can be achieved by making explicit use of `pipe` and `pipeAlloc`.
pub fn trans(client: *Client, comptime Ts: type, cmds: anytype) !Ts {
    return client.transactionImpl(Ts, cmds, .{});
}

/// Like `trans`, but can allocate memory.
pub fn transAlloc(
    client: *Client,
    comptime Ts: type,
    allocator: Allocator,
    cmds: anytype,
) !Ts {
    return transactionImpl(client, Ts, cmds, .{ .ptr = allocator });
}

fn transactionImpl(
    client: *Client,
    comptime Ts: type,
    cmds: anytype,
    allocator: anytype,
) !Ts {
    // TODO: this is not threadsafe.
    _ = try client.send(void, .{"MULTI"});

    try client.pipe(void, cmds);

    if (@hasField(@TypeOf(allocator), "ptr")) {
        return client.sendAlloc(Ts, allocator.ptr, .{"EXEC"});
    } else {
        return client.send(Ts, .{"EXEC"});
    }
}

/// Sends a group of commands more efficiently than sending them one by one.
pub fn pipe(client: *Client, comptime Ts: type, cmds: anytype) !Ts {
    return pipelineImpl(client, Ts, cmds, .{});
}

/// Like `pipe`, but can allocate memory.
pub fn pipeAlloc(
    client: *Client,
    comptime Ts: type,
    allocator: Allocator,
    cmds: anytype,
) !Ts {
    return pipelineImpl(client, Ts, cmds, .{ .ptr = allocator });
}

const Pending = struct {
    ready: bool,
    cond: Io.Condition = .{},
    next: ?*Pending = null,
};

fn pipelineImpl(
    client: *Client,
    comptime Ts: type,
    cmds: anytype,
    opts: anytype, // comptime arg for allocator and one/many commands
) !Ts {
    // TODO: find a way to express some of the metaprogramming requirements
    // in a more clear way. Using @hasField this way is ugly.
    {
        // if (self.broken) return error.BrokenConnection;
        // errdefer self.broken = true;
    }

    try client.wl.lock(client.io);
    var self_pending: Pending = .{ .ready = client.pending_tail == null };
    if (client.pending_tail) |pp| pp.next = &self_pending;
    client.pending_tail = &self_pending;

    {
        // Serialize all commands
        if (@hasField(@TypeOf(opts), "one")) {
            try CommandSerializer.serializeCommand(client.w, cmds);
        } else {
            inline for (std.meta.fields(@TypeOf(cmds))) |field| {
                const cmd = @field(cmds, field.name);
                // try ArgSerializer.serialize(&self.out.stream, args);
                try CommandSerializer.serializeCommand(client.w, cmd);
            }
        }
        try client.w.flush();
    }

    client.wl.unlock(client.io);
    try client.rl.lock(client.io);
    while (!self_pending.ready) {
        try self_pending.cond.wait(client.io, &client.rl);
    }

    defer {
        client.wl.lockUncancelable(client.io);
        defer {
            client.rl.unlock(client.io);
            client.wl.unlock(client.io);
        }
        if (self_pending.next) |np| {
            assert(client.pending_tail.? != &self_pending);
            np.ready = true;
            np.cond.signal(client.io);
        } else {
            assert(client.pending_tail.? == &self_pending);
            client.pending_tail = null;
        }
    }

    // TODO: error procedure
    if (@hasField(@TypeOf(opts), "one")) {
        if (@hasField(@TypeOf(opts), "ptr")) {
            return RESP3.parseAlloc(Ts, opts.ptr, client.r);
        } else {
            return RESP3.parse(Ts, client.r);
        }
    } else {
        var result: Ts = undefined;

        if (Ts == void) {
            const cmd_num = std.meta.fields(@TypeOf(cmds)).len;
            comptime var i: usize = 0;
            inline while (i < cmd_num) : (i += 1) {
                try RESP3.parse(void, client.r);
            }
            return;
        } else {
            switch (@typeInfo(Ts)) {
                .@"struct" => {
                    inline for (std.meta.fields(Ts)) |field| {
                        if (@hasField(@TypeOf(opts), "ptr")) {
                            @field(result, field.name) = try RESP3.parseAlloc(
                                field.type,
                                opts.ptr,
                                client.r,
                            );
                        } else {
                            @field(result, field.name) = try RESP3.parse(
                                field.type,
                                client.r,
                            );
                        }
                    }
                },
                .array => {
                    var i: usize = 0;
                    while (i < Ts.len) : (i += 1) {
                        if (@hasField(@TypeOf(opts), "ptr")) {
                            result[i] = try RESP3.parseAlloc(Ts.Child, opts.ptr, client.r);
                        } else {
                            result[i] = try RESP3.parse(Ts.Child, client.r);
                        }
                    }
                },
                .pointer => |ptr| {
                    switch (ptr.size) {
                        .one => {
                            if (@hasField(@TypeOf(opts), "ptr")) {
                                result = try RESP3.parseAlloc(Ts, opts.ptr, client.r);
                            } else {
                                result = try RESP3.parse(Ts, client.r);
                            }
                        },
                        .many => {
                            if (@hasField(@TypeOf(opts), "ptr")) {
                                result = try opts.alloc(ptr.child, ptr.size);
                                errdefer opts.free(result);

                                for (result) |*elem| {
                                    elem.* = try RESP3.parseAlloc(
                                        Ts.Child,
                                        opts.ptr,
                                        client.r,
                                    );
                                }
                            } else {
                                @compileError("Use sendAlloc / pipeAlloc / transAlloc to decode pointer types.");
                            }
                        },
                    }
                },
                else => @compileError("Unsupported type"),
            }
        }
        return result;
    }
}
