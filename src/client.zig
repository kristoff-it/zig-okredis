const std = @import("std");
const os = std.os;
const net = std.net;
const Allocator = std.mem.Allocator;

const RESP3 = @import("./parser.zig").RESP3Parser;
const CommandSerializer = @import("./serializer.zig").CommandSerializer;
const OrErr = @import("./types/error.zig").OrErr;

pub const Auth = struct {
    user: ?[]const u8,
    pass: []const u8,
};

pub const InitOptions = struct {
    auth: ?Auth = null,
    reader_buffer: []u8,
    writer_buffer: []u8,
};

conn: net.Stream,
reader: net.Stream.Reader,
writer: net.Stream.Writer,

// Connection state
broken: bool = false,

const Client = @This();

/// Initializes a Client on a connection / pipe provided by the user.
pub fn init(conn: net.Stream, options: InitOptions) !Client {
    var client: Client = .{
        .conn = conn,
        .reader = conn.reader(options.reader_buffer),
        .writer = conn.writer(options.writer_buffer),
    };

    if (options.auth) |a| {
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

pub fn close(self: Client) void {
    self.conn.close();
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
    // var heldWrite: std.event.Lock.Held = undefined;
    // var heldRead: std.event.Lock.Held = undefined;
    // var heldReadFrame: @Frame(std.event.Lock.acquire) = undefined;

    // If we're doing async/await we need to first grab the lock
    // for the write stream. Once we have it, we also need to queue
    // for the read lock, but we don't have to acquire it fully yet.
    // For this reason we don't await `self.readLock.acquire()` and in
    // the meantime we start writing to the write stream.
    // if (std_io_is_async) {
    //     heldWrite = self.writeLock.acquire();
    //     heldReadFrame = async self.readLock.acquire();
    // }

    // var heldReadFrameNotAwaited = true;
    // defer if (std_io_is_async and heldReadFrameNotAwaited) {
    //     heldRead = await heldReadFrame;
    //     heldRead.release();
    // };

    {
        // We add a block to release the write lock before we start
        // reading from the read stream.
        // defer if (std_io_is_async) heldWrite.release();

        // Serialize all the commands
        if (@hasField(@TypeOf(opts), "one")) {
            try CommandSerializer.serializeCommand(
                &client.writer.interface,
                cmds,
            );
        } else {
            inline for (std.meta.fields(@TypeOf(cmds))) |field| {
                const cmd = @field(cmds, field.name);
                // try ArgSerializer.serialize(&self.out.stream, args);
                try CommandSerializer.serializeCommand(
                    &client.writer.interface,
                    cmd,
                );
            }
        } // Here is where the write lock gets released by the `defer` statement.
        try client.writer.interface.flush();

        // TODO: locking
        // if (buffering == .Fixed) {
        //     if (std_io_is_async) {
        //         // TODO: see if this stuff can be implemented nicely
        //         // so that you don't have to depend on magic numbers & implementation details.
        //         client.writeLock.mutex.lock();
        //         defer client.writeLock.mutex.unlock();
        //         if (client.writeLock.head == 1) {
        //             try client.writeBuffer.flush();
        //         }
        //     } else {
        //         try client.writeBuffer.flush();
        //     }
        // }
    }

    // if (std_io_is_async) {
    //     heldReadFrameNotAwaited = false;
    //     heldRead = await heldReadFrame;
    // }
    // defer if (std_io_is_async) heldRead.release();

    // TODO: error procedure
    if (@hasField(@TypeOf(opts), "one")) {
        if (@hasField(@TypeOf(opts), "ptr")) {
            return RESP3.parseAlloc(Ts, opts.ptr, client.reader.interface());
        } else {
            return RESP3.parse(Ts, client.reader.interface());
        }
    } else {
        var result: Ts = undefined;

        if (Ts == void) {
            const cmd_num = std.meta.fields(@TypeOf(cmds)).len;
            comptime var i: usize = 0;
            inline while (i < cmd_num) : (i += 1) {
                try RESP3.parse(void, client.reader.interface());
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
                                client.reader.interface(),
                            );
                        } else {
                            @field(result, field.name) = try RESP3.parse(
                                field.type,
                                client.reader.interface(),
                            );
                        }
                    }
                },
                .array => {
                    var i: usize = 0;
                    while (i < Ts.len) : (i += 1) {
                        if (@hasField(@TypeOf(opts), "ptr")) {
                            result[i] = try RESP3.parseAlloc(Ts.Child, opts.ptr, client.reader);
                        } else {
                            result[i] = try RESP3.parse(Ts.Child, client.reader);
                        }
                    }
                },
                .pointer => |ptr| {
                    switch (ptr.size) {
                        .one => {
                            if (@hasField(@TypeOf(opts), "ptr")) {
                                result = try RESP3.parseAlloc(Ts, opts.ptr, client.reader);
                            } else {
                                result = try RESP3.parse(Ts, client.reader);
                            }
                        },
                        .many => {
                            if (@hasField(@TypeOf(opts), "ptr")) {
                                result = try opts.alloc(ptr.child, ptr.size);
                                errdefer opts.free(result);

                                for (result) |*elem| {
                                    elem.* = try RESP3.parseAlloc(Ts.Child, opts.ptr, client.reader);
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

test "docs" {
    @import("std").testing.refAllDecls(Client);
}
