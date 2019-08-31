const std = @import("std");
const heyredis = @import("./src/heyredis.zig");
const Client = heyredis.Client;

pub fn main() !void {
    // Connect
    var client = try Client.initIp4("127.0.0.1", 6379);
    defer client.close();

    //   -
    //   == INTRODUCTION ==
    //   -

    // Send a command, and we're not interested in
    // ispecting the response, so we don't even allocate
    // memory for it. If Redis replies with an error message,
    // this function will return a Zig error.
    try client.send(void, "SET", "key", "42");

    // Get a key, decode the response as an i64.
    // `GET` actually returns a string response, but the
    // parser is nice enough to try and parse it for us.
    // Works with both integers and floats.
    const reply = try client.send(i64, "GET", "key");
    std.debug.warn("key = {}\n", reply);

    // Try to get the value, but this time using an optional type,
    // this allows decoding Redis Nil replies.
    try client.send(void, "DEL", "nokey");
    var maybe = try client.send(?i64, "GET", "nokey");
    if (maybe) |val| {
        std.debug.warn("Found nokey with value = {}\n", val); // Won't be printed.
    } else {
        std.debug.warn("Yep, nokey is not present.\n");
    }

    // To decode strings without allocating, use a FixBuf type.
    // FixBuf is just an array + length, so it allows decoding
    // strings up to its length. If the buffer is not big enough,
    // an error is returned.
    const FixBuf = heyredis.FixBuf;

    try client.send(void, "SET", "stringkey", "Hello World!");
    var stringkey = try client.send(FixBuf(30), "GET", "stringkey");
    std.debug.warn("stringkey = {}\n", stringkey.toSlice());

    // Send a bad command, this time we are interested in the error response.
    // OrErr also has a .Nil case, so you don't need to make your return type
    // optional in this case. In general, wrapping all response types with
    // OrErr() is a good idea.
    const OrErr = heyredis.OrErr;

    switch (try client.send(OrErr(i64), "INCR", "stringkey")) {
        .Ok, .Nil => unreachable,
        .Err => |err| std.debug.warn("error code = {}\n", err.getCode()),
    }

    const MyHash = struct {
        banana: FixBuf(11),
        price: f32,
    };

    // Create a hash with the same fields as our struct
    try client.send(void, "HSET", "myhash", "banana", "yes please", "price", "9.99");

    // Parse it directly into the struct
    switch (try client.send(OrErr(MyHash), "HGETALL", "myhash")) {
        .Nil, .Err => unreachable,
        .Ok => |val| {
            std.debug.warn("myhash = \n\t{?}\n", val);
        },
    }

    // Create a big string key
    try client.send(void, "SET", "divine",
        \\When half way through the journey of our life
        \\I found that I was in a gloomy wood,
        \\because the path which led aright was lost.
        \\And ah, how hard it is to say just what
        \\this wild and rough and stubborn woodland was,
        \\the very thought of which renews my fear!
    );

    // When you are fine with allocating memory,
    // you can use the .sendAlloc interface.
    const allocator = std.heap.direct_allocator;

    // But then it's up to you to free all that was allocated.
    var inferno = try client.sendAlloc([]u8, allocator, "GET", "divine");
    defer allocator.free(inferno);
    std.debug.warn("\ndivine comedy - inferno 1: \n{}\n\n", inferno);

    // When using sendAlloc, you can use OrFullErr to parse not just the error code
    // but also the full error message. The error message is allocated with `allocator`
    // so it will need to be freed. (the next example will free it)
    const OrFullErr = heyredis.OrFullErr;
    var incrErr = try client.sendAlloc(OrFullErr(i64), allocator, "INCR", "divine");
    switch (incrErr) {
        .Ok, .Nil => unreachable,
        .Err => |err| std.debug.warn("error code = {} message = '{}'\n", err.getCode(), err.message),
    }

    // To help deallocating resources allocated by `sendAlloc`, you can use `freeReply`.
    // `freeReply` knows how to deallocate values created by `sendAlloc`.
    const freeReply = heyredis.freeReply;

    // For example, instead of freeing directly incrErr.Err.message, you can do this:
    defer freeReply(incrErr, allocator);

    // In general, sendAlloc will only allocate where the type you specify is a
    // pointer. This call doesn't require to free anything.
    _ = try client.sendAlloc(f64, allocator, "HGET", "myhash", "price");

    // This does require a free
    var allocatedNum = try client.sendAlloc(*f64, allocator, "HGET", "myhash", "price");
    defer freeReply(allocatedNum, allocator);
    // alternatively: defer allocator.destroy(allocatedNum);

    std.debug.warn("allocated num = {} ptr = {}\n", allocatedNum.*, allocatedNum);

    // Now we can decode the reply in a struct that doesn't need a FixBuf
    const MyDynHash = struct {
        banana: []u8,
        price: f32,
    };

    const dynHash = try client.sendAlloc(OrErr(MyDynHash), allocator, "HGETALL", "myhash");
    defer freeReply(dynHash, allocator);

    switch (dynHash) {
        .Nil, .Err => unreachable,
        .Ok => |val| {
            std.debug.warn("mydynhash = \n\t{?}\n", val);
        },
    }
    //   -
    //   == DYNAMIC REPLIES ==
    //   -

    // While most programs will use simple Redis commands, and will know
    // the shape of the reply, one might also be in a situation where the
    // reply is unknown or dynamic. To help with that, supredis includes
    // `DynamicReply`, which can decode any possible Redis reply.
    const DynamicReply = heyredis.DynamicReply;
    var dynReply = try client.sendAlloc(DynamicReply, allocator, "HGETALL", "myhash");
    defer freeReply(dynReply, allocator);

    // DynamicReply is a union that represents all possible replies.
    std.debug.warn("\nmyhash decoded as DynamicReply:\n");
    switch (dynReply.data) {
        .Nil, .Bool, .Number, .Double, .Bignum, .String, .List, .Set => {},
        .Map => |kvs| {
            for (kvs) |kv| {
                std.debug.warn("\t[{}] => '{}'\n", kv.key.data.String.string, kv.value.data.String);
            }
        },
    }

    // KV can also be used outside of DynamicReply.
    const KV = heyredis.KV;

    // In the previous example we saw how a Redis hashmap can become
    // a sequence of KV values. The same applies to lists containing
    // an even number of elements (and with appropriate typing).
    // A good example are sorted sets.
    try client.send(void, "DEL", "sset");
    try client.send(void, "ZADD", "sset", "100", "elem1", "200", "elem2");

    std.debug.warn("\n\nSorted set to KV slice:\n");
    const sortSet = try client.sendAlloc([]KV([]u8, f64), allocator, "ZRANGE", "sset", "0", "1", "WITHSCORES");
    defer freeReply(sortSet, allocator);

    for (sortSet) |kv| {
        std.debug.warn("\t[{}] => {}\n", kv.key, kv.value);
    }

    // Combining the tools at our disposal we could run again the
    // previous command without requiring dynamic allocations.
    std.debug.warn("\n\nAgain, but no allocator this time:\n");
    for (try client.send([2]KV(FixBuf(100), f64), "ZRANGE", "sset", "0", "1", "WITHSCORES")) |kv| {
        std.debug.warn("\t[{}] => {}\n", kv.key.toSlice(), kv.value);
    }
}
