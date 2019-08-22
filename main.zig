const std = @import("std");
const Client = @import("./src/client.zig").Client;
const OrErr = @import("./src/types/error.zig").OrErr;
const FixBuf = @import("./src/types/fixbuf.zig").FixBuf;

pub fn main() !void {
    // Connect
    var client = try Client.initIp4("127.0.0.1", 6379);
    defer client.close();

    // Send a command, and we're not interested in
    // ispecting the response, so we don't even allocate
    // memory for it. If Redis replies with an error message,
    // this function will return a Zig error.
    try client.send(void, "SET key 42");

    // Get a key, decode the response as an i64.
    // `GET` actually returns a string response, but the
    // parser is nice enough to try and parse it for us.
    // Works with both integers and floats.
    const reply = try client.send(i64, "GET key");
    std.debug.warn("key = {}\n", reply);

    // Esure that `nokey` doesn't exist
    try client.send(void, "DEL nokey");

    // Try to get the value, but this time using an optional type,
    // this allows decoding Redis Nil replies.
    var maybe = try client.send(?i64, "GET nokey");
    if (maybe) |val| {
        std.debug.warn("Found nokey with value = {}\n", val); // Won't be printed.
    } else {
        std.debug.warn("Yep, nokey is not present.\n");
    }

    // To decode strings without allocating, use a FixBuf type.
    // FixBuf is just an array + length, so it allows decoding
    // strings up to its length. If the buffer is not big enough,
    // an error is returned.
    try client.send(void, "SET stringkey 'Hello World!'");
    var stringkey = try client.send(FixBuf(30), "GET stringkey");
    std.debug.warn("stringkey = {}\n", stringkey.toSlice());

    // Send a bad command, this time we are interested in the error response.
    // OrErr also has a .Nil case, so you don't need to make your return type
    // optional in this case. In general, wrapping all response types with
    // OrErr() is a good idea.
    switch (try client.send(OrErr(i64), "INCR stringkey")) {
        .Ok, .Nil => unreachable,
        .Err => |err| std.debug.warn("error code = {}\n", err.getCode()),
    }

    const MyHash = struct {
        banana: FixBuf(11),
        price: f32,
    };

    // Create a hash with the same fields as our struct
    try client.send(void, "HSET myhash banana 'yes please' price 9.99");

    // Parse it directly into the struct
    switch (try client.send(OrErr(MyHash), "HGETALL myhash")) {
        .Nil, .Err => unreachable,
        .Ok => |val| {
            std.debug.warn("myhash = \n\t{?}\n", val);
        },
    }

    // Normally, you probably are fine with allocating memory,
    // and don't want to have to preemptively size FixBufs.
    const allocator = std.heap.direct_allocator;

    try client.send(void, "SET divine 'When half way through the journey of our life - I found that I was in a gloomy wood'");

    // Using parseAlloc you can dynamically parse replies from Redis,
    // But then it's up to you to free all that was allocated.
    var inferno = try client.sendAlloc([]u8, allocator, "GET divine");
    defer allocator.free(inferno);
    std.debug.warn("dine comedy - inferno 1: \n{}\n\n", inferno);

    // When using .parseAlloc, OrErr will store not just the error code
    // but also the full error message. That too needs to be freed, of course.
    // Note that the OrErr union is not dynamically allocated, only the message.
    var incrErr = try client.sendAlloc(OrErr(i64), allocator, "INCR divine");
    defer incrErr.freeErrorMessage(allocator);
    switch (incrErr) {
        .Ok, .Nil => unreachable,
        .Err => |err| std.debug.warn("error code = {} message = '{}'\n", err.getCode(), err.message.?),
    }

    // In general, .sendAlloc will only allocate where the type you specify is a
    // pointer. This call doesn't requere any free.
    _ = try client.sendAlloc(f64, allocator, "HGET myhash price");

    // This does require a free
    var allocatedNum = try client.sendAlloc(*f64, allocator, "HGET myhash price");
    defer allocator.destroy(allocatedNum);
    std.debug.warn("allocated num = {} ptr = {}\n", allocatedNum.*, allocatedNum);

    // Now we can deserialize in a struct that doesn't need a FixBuf
    const MyDynHash = struct {
        banana: []u8,
        price: f32,
    };

    switch (try client.sendAlloc(OrErr(MyDynHash), allocator, "HGETALL myhash")) {
        .Nil, .Err => unreachable,
        .Ok => |val| {
            // ... but we do need to free the dynamically allocated memory
            defer allocator.free(val.banana);
            std.debug.warn("mydynhash = \n\t{?}\n", val);
        },
    }
}
