const std = @import("std");
const net = std.net;
const okredis = @import("./src/okredis.zig");
const Client = okredis.Client;

pub fn main() !void {
    // Connect
    const addr = try net.Address.parseIp4("127.0.0.1", 6379);
    var connection = try net.tcpConnectToAddress(addr);

    var client: Client = undefined;
    try client.init(connection);
    defer client.close();

    //   -
    //   == INTRODUCTION ==
    //   -

    // Send a command, and we're not interested in
    // ispecting the response, so we don't even allocate
    // memory for it. If Redis replies with an error message,
    // this function will return a Zig error.
    try client.send(void, .{ "SET", "key", "42" });

    // Get a key, decode the response as an i64.
    // `GET` actually returns a string response, but the
    // parser is nice enough to try and parse it for us.
    // Works with both integers and floats.
    const reply = try client.send(i64, .{ "GET", "key" });
    std.debug.print("key = {}\n", .{reply});

    // Try to get the value, but this time using an optional type,
    // this allows decoding Redis Nil replies.
    try client.send(void, .{ "DEL", "nokey" });
    var maybe = try client.send(?i64, .{ "GET", "nokey" });
    if (maybe) |val| {
        std.debug.print("Found nokey with value = {}\n", .{val}); // Won't be printed.
    } else {
        std.debug.print("Yep, nokey is not present.\n", .{});
    }

    // To decode strings without allocating, use a FixBuf type.
    // FixBuf is just an array + length, so it allows decoding
    // strings up to its length. If the buffer is not big enough,
    // an error is returned.
    const FixBuf = okredis.types.FixBuf;

    try client.send(void, .{ "SET", "stringkey", "Hello World!" });
    var stringkey = try client.send(FixBuf(30), .{ "GET", "stringkey" });
    std.debug.print("stringkey = {s}\n", .{stringkey.toSlice()});

    // Send a bad command, this time we are interested in the error response.
    // OrErr also has a .Nil case, so you don't need to make your return type
    // optional in this case. In general, wrapping all response types with
    // OrErr() is a good idea.
    const OrErr = okredis.types.OrErr;

    switch (try client.send(OrErr(i64), .{ "INCR", "stringkey" })) {
        .Ok, .Nil => unreachable,
        .Err => |err| std.debug.print("error code = {s}\n", .{err.getCode()}),
    }

    const MyHash = struct {
        banana: FixBuf(11),
        price: f32,
    };

    // Create a hash with the same fields as our struct
    try client.send(void, .{ "HSET", "myhash", "banana", "yes please", "price", "9.99" });

    // Parse it directly into the struct
    switch (try client.send(OrErr(MyHash), .{ "HGETALL", "myhash" })) {
        .Nil, .Err => unreachable,
        .Ok => |val| {
            std.debug.print("myhash = \n\t{}\n", .{val});
        },
    }

    // Create a big string key
    try client.send(void, .{
        "SET",
        "divine",
        \\When half way through the journey of our life
        \\I found that I was in a gloomy wood,
        \\because the path which led aright was lost.
        \\And ah, how hard it is to say just what
        \\this wild and rough and stubborn woodland was,
        \\the very thought of which renews my fear!
    });

    // When you are fine with allocating memory,
    // you can use the .sendAlloc interface.
    const allocator = std.heap.page_allocator;

    // But then it's up to you to free all that was allocated.
    var inferno = try client.sendAlloc([]u8, allocator, .{ "GET", "divine" });
    defer allocator.free(inferno);
    std.debug.print("\ndivine comedy - inferno 1: \n{s}\n\n", .{inferno});

    // When using sendAlloc, you can use OrFullErr to parse not just the error code
    // but also the full error message. The error message is allocated with `allocator`
    // so it will need to be freed. (the next example will free it)
    const OrFullErr = okredis.types.OrFullErr;
    var incrErr = try client.sendAlloc(OrFullErr(i64), allocator, .{ "INCR", "divine" });
    switch (incrErr) {
        .Ok, .Nil => unreachable,
        .Err => |err| std.debug.print("error code = {s} message = '{s}'\n", .{ err.getCode(), err.message }),
    }

    // To help deallocating resources allocated by `sendAlloc`, you can use `freeReply`.
    // `freeReply` knows how to deallocate values created by `sendAlloc`.
    const freeReply = okredis.freeReply;

    // For example, instead of freeing directly incrErr.Err.message, you can do this:
    defer freeReply(incrErr, allocator);

    // In general, sendAlloc will only allocate where the type you specify is a
    // pointer. This call doesn't require to free anything.
    _ = try client.sendAlloc(f64, allocator, .{ "HGET", "myhash", "price" });

    // This does require a free
    var allocatedNum = try client.sendAlloc(*f64, allocator, .{ "HGET", "myhash", "price" });
    defer freeReply(allocatedNum, allocator);
    // alternatively: defer allocator.destroy(allocatedNum);

    std.debug.print("allocated num = {} ptr = {}\n", .{ allocatedNum.*, allocatedNum });

    // Now we can decode the reply in a struct that doesn't need a FixBuf
    const MyDynHash = struct {
        banana: []u8,
        price: f32,
    };

    const dynHash = try client.sendAlloc(OrErr(MyDynHash), allocator, .{ "HGETALL", "myhash" });
    defer freeReply(dynHash, allocator);

    switch (dynHash) {
        .Nil, .Err => unreachable,
        .Ok => |val| {
            std.debug.print("mydynhash = \n\t{any}\n", .{val});
        },
    }
    //   -
    //   == DYNAMIC REPLIES ==
    //   -

    // While most programs will use simple Redis commands, and will know
    // the shape of the reply, one might also be in a situation where the
    // reply is unknown or dynamic. To help with that, supredis includes
    // `DynamicReply`, which can decode any possible Redis reply.
    const DynamicReply = okredis.types.DynamicReply;
    var dynReply = try client.sendAlloc(DynamicReply, allocator, .{ "HGETALL", "myhash" });
    defer freeReply(dynReply, allocator);

    // DynamicReply is a union that represents all possible replies.
    std.debug.print("\nmyhash decoded as DynamicReply:\n", .{});
    switch (dynReply.data) {
        .Nil, .Bool, .Number, .Double, .Bignum, .String, .List, .Set => {},
        .Map => |kvs| {
            for (kvs) |kv| {
                std.debug.print("\t[{s}] => '{s}'\n", .{ kv[0].data.String.string, kv[1].data.String });
            }
        },
    }

    // Pipelining is a way of sending a batch of commands to Redis
    // in a more performant way than sending them one by one.
    // It's especially useful when using blocking I/O but, it can also
    // give small boosts when doing evented I/O.
    const r1 = try client.pipe(struct {
        c1: void,
        c2: u64,
        c3: OrErr(FixBuf(10)),
    }, .{
        .{ "SET", "counter", 0 },
        .{ "INCR", "counter" },
        .{ "ECHO", "banana" },
    });
    std.debug.print("\n\n[INCR => {}]\n", .{r1.c2});
    std.debug.print("[ECHO => {s}]\n", .{r1.c3});

    // You can also allocate when doing pipelining.
    const r2 = try client.pipeAlloc(struct {
        c1: void,
        value: []u8,
    }, allocator, .{
        .{ "SET", "banana", "yes please" },
        .{ "GET", "banana" },
    });
    defer freeReply(r2, allocator);

    std.debug.print("\n[banana] => '{s}'\n", .{r2.value});

    // Transactions are a way of providing isolation and all-or-nothing semantics to
    // a group of Redis commands. The relative methods (`trans` and `transAlloc`) are
    // included mostly for convenience as they implicitly apply pipelining to the
    // commands passed, but the same result could be achieved by making explicit use
    // of MULTI/EXEC and `pipe`/`pipeAlloc`.
    switch (try client.trans(OrErr(struct {
        c1: OrErr(FixBuf(10)),
        c2: u64,
        c3: OrErr(void),
    }), .{
        .{ "SET", "banana", "no, thanks" },
        .{ "INCR", "counter" },
        .{ "INCR", "banana" },
    })) {
        .Err => |e| @panic(e.getCode()),
        .Nil => @panic("got nil"),
        .Ok => |tx_reply| {
            std.debug.print("\n[SET = {s}] [INCR = {}] [INCR (error) = {s}]\n", .{
                tx_reply.c1.Ok.toSlice(),
                tx_reply.c2,
                tx_reply.c3.Err.getCode(),
            });
        },
    }
}
