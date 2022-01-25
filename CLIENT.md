# Using the OkRedis client

## Table of contents
   * [Connecting](#connecting)
   * [Buffering](#buffering)
   * [Evented vs blocking I/O](#evented-vs-blocking-io)
   * [Pipelining](#pipelining)
   * [Transactions](#transactions)
   * [Pub/Sub](#pubsub)

## Connecting
For now only IPv4 is supported, in the near future I'll add support for the 
common options.

```zig
const std = @import("std");
const okredis = @import("./src/okredis.zig");
const Client = okredis.Client;

pub fn main() !void {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 6379);
    var connection = try std.net.tcpConnectToAddress(addr);
    
    var client: Client = undefined;
    try client.init(connection);
    defer client.close();

    try client.send(void, .{ "SET", "key", "42" });

    const reply = try client.send(i64, .{ "GET", "key" });
    std.debug.warn("key = {}\n", .{reply});
}
```

## Buffering
Currently the client uses a 4096 bytes long fixed buffer embedded in the 
`Client` struct. 

In the future the option of customizing the buffering strategy will be exposed 
to the user, once the I/O stream interface becomes more stable in Zig.

## Evented vs blocking I/O
Evented I/O is supported and the client will properly coordinate with the
event loop when `pub const io_mode = .evented;` is defined in the root file.

The implementation has only been tested lightly, so it's recommended to wait for 
the Zig ecosystem to stabilize more before relying on this feature (which at the
time of writing only works on Linux).

## Pipelining
Redis supports pipelining, which, in short, consists of sending multiple 
commands at once and only reading replies once all the commands are sent.
[You can read more here](https://redis.io/topics/pipelining).

OkRedis exposes pipelining through `pipe` and `pipeAlloc`.

```zig
const reply = try client.pipe(struct {
    c1: void,
    c2: u64,
    c3: OrErr(FixBuf(10)),
}, .{
    .{ "SET", "counter", 0 },
    .{ "INCR", "counter" },
    .{ "ECHO", "banana" },
});

std.debug.print("[INCR => {}]\n", .{reply.c2});
std.debug.print("[ECHO => {s}]\n", .{reply.c3.toSlice()});
```

Let's break down the code above.
The first argument to `pipe` is a struct *definition* that contains one field 
for each command being sent through the pipeline. It's basically the same as 
with `send`, except that, since we're sending multiple commands at once, the 
return type must comprehend the return types of all commands.

You can define whatever field name you want when defining the return types.
In the example above I chose (`c1`, `c2`, `c3`), but whichever is fine.

The second argument to `pipe` is an argument list that contains all the commands
that we want to send.

Pipelines are multi-command invocations so each command will succeed or fail 
independently. This is a small but big difference with transactions, as we will 
see in the next section.

## Transactions
Transactions are a way of providing isolation and all-or-nothing semantics to a
group of Redis commands. The concept of transactions is orthogonal to pipelines,
but given the semantics of Redis transactions, it's often advantageous to apply
pipelining to one.

You can [read more about Redis transactions here](https://redis.io/topics/transactions).

OkRedis provides `trans` and `transAlloc` to perform transactions with automatic
pipelining. It's mostly for convenience as the same result could be achieved by
making explicit use of `MULTI`, `EXEC` and (optionally) `pipe`/`pipeAlloc`.

```zig
const reply = try client.trans(OrErr(struct {
    c1: OrErr(FixBuf(10)),
    c2: u64,
    c3: OrErr(void),
}), .{
    .{ "SET", "banana", "no, thanks" },
    .{ "INCR", "counter" },
    .{ "INCR", "banana" },
});

switch (reply) {
    .Err => |e| @panic(e.getCode()),
    .Nil => @panic("got nil"),
    .Ok => |r| {
        std.debug.print("\n[SET = {s}] [INCR = {}] [INCR (error) = {s}]\n", .{
            r.c1.Ok.toSlice(),
            r.c2,
            r.c3.Err.getCode(),
        });
    },
}
```

At first sight the return value works the same way as with pipelining, but there
is one important difference: the whole transaction can return an error or `nil`.
When the transaction gets committed, the result can be:

1. A Redis error, in case an error was already encountered when queueing commands.
2. `nil`, in case the transaction was preceded by a `WATCH` that triggered.
3. A list of results, each corresponding to a command in the transaction.

For this reason it's recommended to wrap a transaction's return type in `OrErr`.

If the return type of all commands is the same, you can also use arrays or 
slices (for slices you'll need `pipeAlloc` or `transAlloc`).

```zig
// Maybe not the most important transaction of them all...
const reply = try client.transAlloc(OrErr([][]u8), allocator, .{
    .{ "ECHO", "Do you" },
    .{ "ECHO", "want to" },
    .{ "ECHO", "build a" },
    .{ "ECHO", "client?" },
});

// Don't forget to free the memory!
defer okredis.freeReply(reply);

// Switch over the result.
switch (reply) {
    .Err => |e| @panic(e.getCode()),
    .Nil => @panic("got nil"),
    .Ok => |r| {
        for (r) |msg| {
            std.debug.print("{s} ", .{msg});
        }
        std.debug.print("\n", .{});
    },
}
```

This prints, as you might have guessed:
```
Do you want to build a client?
```

## Pub/Sub
Pub/Sub is not implemented yet. 

I'm still trying to figure out how the API should look like in order to 
provide an allocation-free interface also for Pub/Sub.

In case I can't make progress in the near future, I'll add some low-level 
APIs (similar to what hiredis provides) to make the functionality available in
the meantime.