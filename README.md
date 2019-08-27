# Hey Redis
Experimental Redis client for Zig (Requires Redis from unstable branch)

## Handy and Efficient
This client has two main goals:
1. Offer an interface with great ergonomics
2. Don't be wasteful for the sake of ease of use

## Zero dynamic allocations, unless explicitly wanted

The client has two functions to send commands: `send` and `sendAlloc`. Following Zig's mantra of making dynamic allocations explicit, only `sendAlloc` can allocate dynamic memory, and only does so by using a user-provided allocator. 

This library makes heavy use of Zig's comptile-time facilities, I wrote a blog post about the subject: https://kristoff.it/blog/what-is-zig-comptime.

## Quickstart

```zig
const std = @import("std");
const heyredis = @import("./src/heyredis.zig");
const Client = heyredis.Client;

pub fn main() !void {
    var client = try Client.initIp4("127.0.0.1", 6379);
    defer client.close();

    try client.send(void, "SET", "key", "42");

    const reply = try client.send(i64, "GET", "key");
}
```

## Simple and efficient reply decoding

The first argument to the `send` / `sendAlloc` function is a type which defines how to decode the reply from Redis.

### Void

By using `void`, we indicate that we're not interested in inspecting the response, so we don't even allocate memory in the function's frame for it. If Redis replies with an error message, this  function will return a Zig error.

```zig
try client.send(void, "SET", "key", "42");
```

### Numbers

Get a key, decode the response as an i64. `GET` actually returns a string response, so the parser tries to use `fmt.parse{Int,Float}`.

```zig
const reply = try client.send(i64, "GET", "key");
```

### Optionals

Optional types let you decode `nil` replies from Redis.

```zig
try client.send(void, "DEL", "nokey");
var maybe = try client.send(?i64, "GET", "nokey");
if (maybe) |val| {
    unreachable;
} else {
    // Yep, the value is missing.
}
```

### Strings

To decode strings without allocating, use a `FixBuf` type. `FixBuf` is just an array + length, so it allows decoding strings up to its length. If the buffer is not big enough, an error is returned.

```zig
const FixBuf = heyredis.FixBuf;

try client.send(void, "SET", "stringkey", "Hello World!");
var stringkey = try client.send(FixBuf(30), "GET", "stringkey");
std.debug.warn("stringkey = {}\n", stringkey.toSlice());
```

### Redis Errors

Sending a command that causes an error will produce a Zig error, but in that case you won't be able to inspect the actual error code. Use `OrErr` to parse  Redis errors as values. `OrErr` also has a `.Nil` case, so you don't need to wrap the inner type with an optional. In general it's a good idea to wrap most reply types with `OrErr`. 

```zig
const OrErr = heyredis.OrErr;

switch (try client.send(OrErr(i64), "INCR", "stringkey")) {
    .Ok, .Nil => unreachable,
    .Err => |err| std.debug.warn("error code = {}\n", err.getCode()),
}
```

### Redis OK replies
`OrErr(void)` is a good way of decoding `OK` replies from Redis in case you want to inspect error codes. If you don't care about error codes, a simple `void` will do, but in that case an error reply will produce `error.GotErrorReply`, which, if not explicitly checked, will cause the calling function to return with an error.


### Structs

Map types in Redis (e.g., Hashes, Stream entries) can be decoded into struct types.

```zig
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
        std.debug.warn("{?}", val);
    },
}
```

The code above prints:

```
MyHash{ .banana = src.types.fixbuf.FixBuf(11){ .buf = yes please�, .len = 10 }, .price = 9.98999977e+00 }
```

This feature has two implementations: 
- Slower but safe: store each field name and string compare with each map field.
- Fast but unsafe: use perfect hashing to match map field and struct field in O(1).

The perfect hashing feature is currently just a PoC and breaks for big structs.

## Allocating memory

The examples above perform zero allocations but consequently make it awkward to work with strings. Using `sendAlloc`, you can allocate dynamic memory every time the reply type is a pointer or a slice.

### Allocating Strings

```zig
const allocator = std.heap.direct_allocator;

// Create a big string key
try client.send(void, "SET", "divine",
    \\When half way through the journey of our life
    \\I found that I was in a gloomy wood,
    \\because the path which led aright was lost.
    \\And ah, how hard it is to say just what
    \\this wild and rough and stubborn woodland was,
    \\the very thought of which renews my fear!
);

var inferno = try client.sendAlloc([]u8, allocator, "GET", "divine");
defer allocator.free(inferno);

// This call doesn't require to free anything.
_ = try client.sendAlloc(f64, allocator, "HGET", "myhash", "price");

// This does require a free
var allocatedNum = try client.sendAlloc(*f64, allocator, "HGET", "myhash", "price");
defer allocator.destroy(allocatedNum);
```

### Freeing complex replies

The previous examples produced types that are easy to free. Later we will see more complex examples where it becomes tedious to free everything by hand. For this reason heyredis includes `freeReply`, which frees recursively a value produced by `sendAlloc`. The following examples will showcase how to use it.

```zig
const freeReply = heyredis.freeReply;
```

### Allocating Redis Error messages

When using `OrErr`, we were only decoding the error code and throwing away the message. Using `OrFullErr` you will also be able to inspect the full error message. The error code doesn't need to be freed (it's written to a FixBuf), but the error message will need to be freed.

```zig
const OrFullErr = heyredis.OrFullErr;

var incrErr = try client.sendAlloc(OrFullErr(i64), allocator, "INCR", "divine");
defer freeReply(incErr, allocator);

switch (incrErr) {
    .Ok, .Nil => unreachable,
    .Err => |err| {
        // Alternative manual deallocation: 
        // defer allocator.free(err.message.?)
        std.debug.warn("error code = '{}'\n", err.getCode());
        std.debug.warn("error message = '{}'\n", err.message.?);
    },
}
```
The error code doesn't need to be freed because `OrErr` and `OrFullErr` are unions over the input type. Since the error is mutually exclusive with a succesful reply, we reutilize the same memory to store the error code. The error message, being something that should not relied upon programmatically,
is ignored unless you use `OrFullErr`.

The code above will print:

```
error code = 'ERR' 
error message = 'value is not an integer or out of range'
```

### Allocating structured types

Previously when we wanted to decode a struct we had to use a `FixBuf` to decode a string field. Now we can just do it the normal way.

```zig
const MyDynHash = struct {
    banana: []u8,
    price: f32,
};

const dynHash = try client.sendAlloc(OrErr(MyDynHash), allocator, "HGETALL", "myhash");
defer freeReply(dynHash, allocator);

switch (dynHash) {
    .Nil, .Err => unreachable,
    .Ok => |val| std.debug.warn("{?}", val),
}
```

The code above will print:

```
MyDynHash{ .banana = yes please, .price = 9.98999977e+00 }
```

## Dynamic Replies

While most programs will use simple Redis commands and will know the shape of the reply, one might also be in a situation where the reply is unknown or dynamic. To help with that, heyredis includes `DynamicReply`, which can decode any possible Redis reply.

```zig
const DynamicReply = heyredis.DynamicReply;

const dynReply = try client.sendAlloc(DynamicReply, allocator, "HGETALL", "myhash");
defer freeReply(dynReply, allocator);

switch (dynReply) {
    .Nil, .Bool, .Number, .Double, .String, .List => {},
    .Map => |kvs| {
        for (kvs) |kv| {
            std.debug.warn("[{}] => '{}'\n", kv.key.String, kv.value.String);
        }
    },
}
```

The code above will print:

```
[banana] => 'yes please'
[price] => '9.99'
```

`DynamicReply` is a union. These are the possible cases:

```zig
// Nil: void
// Bool: bool
// Number: i64
// Double: f64
// String: []u8
// Map: []KV(DynamicReply, DynamicReply)
// List: []DynamicReply
```

`KV` is a simple Key-Value struct. It can also be used independently of `DynamicReply`

### Decoding Sorted Set commands WITHSCORES into KV
Calling commands like `ZRANGE` with the `WITHSCORES` option will make Redis reply with a list of couples containing member and score.
`KV` knows how to decode itself from couples (RESP lists of length 2).

```zig
try client.send(void, "ZADD", "sset", "100", "elem1", "200", "elem2");

const sortSet = try client.sendAlloc([]KV([]u8, f64), allocator, "ZRANGE", "sset", "0", "1", "WITHSCORES");
defer freeReply(sortSet, allocator);

for (sortSet) |kv| {
    std.debug.warn("[{}] => {}\n", kv.key, kv.value);
}
```

The code above will print:
```
[elem1] => 1.0e+02
[elem2] => 2.0e+02
```

## Decoding rules
You saw a few different ways of decoding Redis replies. The parser can decode simple types in a straightforward way. In case of numbers, if the reply is a string, the parser tries to use `fmt.parseInt` or `fmt.parseFloat`, depending on the type requested.

- Arrays can decode sequences (RESP lists or strings) as long as the length matches exactly.
- Slices can decode sequences without restrictions in terms of length, but they require an allocator.
- Structs can decode Map types as long as the fields match perfectly.

Types like `FixBuf(N)`, `DynamicReply`, `OrErr(T)`/`OrFullErr(T)` and `KV(K, V)` can decode themselves using custom logic because they implement the `Redis.Parser` trait.

## Decoding custom types
TODO


## Decoding types from the standard library
TODO

## TODOS
- Add all RESP3 types
- Design Zig errors
- Add safety checks when the command is comptime known (e.g. SET takes only 2 arguments)
- More support for stdlib types (buffer, hashmap, bignum, ...)
- Better connection handling (buffering, ...)
- Support for async/await
- Pub/Sub
- Attributes
- Cluster client
- Sentinel client
- Refine the Redis traits
