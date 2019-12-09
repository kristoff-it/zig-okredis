
<h1 align="center">Hey Redis</h1>
<p align="center">
    <a href="LICENSE"><img src="https://badgen.net/github/license/kristoff-it/zig-heyredis" /></a>
    <a href="https://twitter.com/croloris"><img src="https://badgen.net/badge/twitter/@croloris/1DA1F2?icon&label" /></a>
</p>

<p align="center">
    Zero-allocation client for Redis 6+
</p>

## Handy and Efficient
This client aims to offer an interface with great ergonomics without compromising on performance.


## Zero dynamic allocations, unless explicitly wanted

The client has two main interfaces to send commands: `send` and `sendAlloc`. Following Zig's mantra of making dynamic allocations explicit, only `sendAlloc` can allocate dynamic memory, and only does so by using a user-provided allocator. 

The way this is achieved is by making good use of RESP3's typed responses and Zig's metaprogramming facilities.
The library uses compile-time reflection to specialize down to the parser level, allowing heyredis to decode whenever possible a reply directly into a function frame, **without any intermediate dynamic allocation**. If you want more information about Zig's comptime:
- [Official documentation](https://ziglang.org/documentation/master/#comptime)
- [What is Zig's Comptime?](https://kristoff.it/blog/what-is-zig-comptime) (blog post written by me)

By using `sendAlloc` you can decode replies with arbrirary shape at the cost of occasionally performing dynamic allocations. The interface takes an allocator as input, so the user can setup custom allocation schemes such as [arenas](https://en.wikipedia.org/wiki/Region-based_memory_management).

## Quickstart

```zig
const std = @import("std");
const heyredis = @import("./src/heyredis.zig");
const SET = heyredis.commands.SET;
const OrErr = heyredis.OrErr;
const Client = heyredis.Client;

pub fn main() !void {
    var client: Client = undefined;
    try client.initIp4("127.0.0.1", 6379);
    defer client.close();

    // Base interface
    try client.send(void, .{ "SET", "key", "42" });
    const reply = try client.send(i64, .{ "GET", "key" });
    if (reply != 42) @panic("out of towels");


    // Command builder interface
    const cmd = SET.init("key", "43", .NoExpire, .IfAlreadyExisting);
    const otherReply = try client.send(OrErr(void), cmd);
    switch (otherReply) {
        .Nil => @panic("command should not have returned nil"),
        .Err => @panic("command should not have returned an error"),
        .Ok => std.debug.warn("success!"),
    }
}
```

## Simple and efficient reply decoding

The first argument to `send` / `sendAlloc` is a type which defines how to decode the reply from Redis.

### Void

By using `void`, we indicate that we're not interested in inspecting the reply, so we don't even reserve memory in the function's frame for it. This will discard any reply Redis might send, **except for error replies**. If an error reply is recevied, the function will return `error.GotErrorReply`. Later we will see how to decode Redis error replies as values.

```zig
try client.send(void, .{ "SET", "key", "42" });
```

### Numbers

Numeric replies can be decoded directly to Integer or Float types. If Redis replies with a string, the parser will try to parse a number out of it using  `fmt.parse{Int,Float}` (this is what happens with `GET`).

```zig
const reply = try client.send(i64, .{ "GET", "key" });
```

### Optionals

Optional types let you decode `nil` replies from Redis. When the expected type is not an optional, and Redis replies with a `nil`, then `error.GotNilReply` is returned instead. This is equivalent to how error replies are decoded: if the expected type doesn't account for the possibility, a Zig error is returned.

```zig
try client.send(void, .{ "DEL", "nokey" });
var maybe = try client.send(?i64, .{ "GET", "nokey" });
if (maybe) |val| {
    unreachable;
} else {
    // Yep, the value is missing.
}
```

### Strings

Decoding strings without allocating is a bit trickier. It's possible to decode a string inside an array, but the two lengths must match, as there is no way to otherwise indicate the point up to which the array was filled.

For your convenience the library bundles a generic type called `FixBuf(N)`. A `FixBuf(N)` just an array of size `N` + a length, so it allows decoding strings shorter than `N` by using the length to mark where the string ends. If the buffer is not big enough, an error is returned. We will later see how types like `FixBuf(N)` can implement custom decoding logic.

```zig
const FixBuf = heyredis.FixBuf;

try client.send(void, "SET", .{ "hellokey", "Hello World!" });
const hello = try client.send(FixBuf(30), .{ "GET", "hellokey" });

// .toSlice() lets you address the string inside FixBuf
if(std.mem.eql(u8, "Hello World!", hello.toSlice())) { 
    // Yep, the string was decoded
} else {
    unreachable;
}

// Alternatively, if the string has a known fixed length
const helloArray = try client.send([12]u8, .{ "GET", "hellokey" });
if(std.mem.eql(u8, "Hello World!", helloArray[0..])) { 
    // Yep, the string was decoded
} else {
    unreachable;
}
```

### Redis Errors

We saw before that receiving an error reply from Redis causes a Zig error: `error.GotErrorReply`. This is because the types we tried to decode the reply into did not account for the possiblity of an error reply. Error replies are just strings with a `<ERROR CODE> <error message>` structure (e.g. "ERR unknown command"), but are tagged as errors in the underlying RESP protocol. While it would be possible to decode them as normal strings, the parser doesn't support that possibility for two reasons:

1. Silently decoding errors as strings would make error-checking *mistake*-prone.
2. Errors should be programmatically inspected only by looking at the code.

To decode error replies heyredis bundles `OrErr(T)`, a generic type that wraps your expected return type inside a union. The union has three cases:

- `.Ok` for when the command succeeds, contains `T`
- `.Err` for when the reply is an error, contains the error code
- `.Nil` for when the reply is `nil`

The last case is there just for convenience, as it's basically equivalent to making the expected return type an optional.
In general it's a good idea to wrap most reply types with `OrErr`. 

```zig
const OrErr = heyredis.OrErr;

switch (try client.send(OrErr(i64), .{ "INCR", "stringkey" })) {
    .Ok, .Nil => unreachable,
    .Err => |err| std.debug.warn("error code = {}\n", err.getCode()),
}
```

### Redis OK replies

`OrErr(void)` is a good way of decoding `OK` replies from Redis in case you want to inspect error codes. If you don't care about error codes, a simple `void` will do, but in that case an error reply will produce `error.GotErrorReply`.

### Structs

Map types in Redis (e.g., Hashes, Stream entries) can be decoded into struct types.

```zig
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
Perfect hashing is a razor-sharp option for advanced users that know **for sure** that the data in Redis matches expectations -- or that are willing to live with the potential consequences of a mismatch.

## Allocating memory

The examples above perform zero allocations but consequently make it awkward to work with strings. Using `sendAlloc`, you can allocate dynamic memory every time the reply type is a pointer or a slice.

### Allocating Strings

```zig
const allocator = std.heap.direct_allocator;

// Create a big string key
try client.send(void, .{ "SET", "divine",
    \\When half way through the journey of our life
    \\I found that I was in a gloomy wood,
    \\because the path which led aright was lost.
    \\And ah, how hard it is to say just what
    \\this wild and rough and stubborn woodland was,
    \\the very thought of which renews my fear!
});

var inferno = try client.sendAlloc([]u8, allocator, .{ "GET", "divine" });
defer allocator.free(inferno);

// This call doesn't require to free anything.
_ = try client.sendAlloc(f64, allocator, .{ "HGET", "myhash", "price" });

// This does require a free
var allocatedNum = try client.sendAlloc(*f64, allocator, .{ "HGET", "myhash", "price" });
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

var incrErr = try client.sendAlloc(OrFullErr(i64), allocator, .{ "INCR", "divine" });
defer freeReply(incErr, allocator);

switch (incrErr) {
    .Ok, .Nil => unreachable,
    .Err => |err| {
        // Alternative manual deallocation: 
        // defer allocator.free(err.message)
        std.debug.warn("error code = '{}'\n", err.getCode());
        std.debug.warn("error message = '{}'\n", err.message);
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

const dynHash = try client.sendAlloc(OrErr(MyDynHash), allocator, .{ "HGETALL", "myhash" });
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

While most programs will use simple Redis commands and will know the shape of the reply, one might also be in a situation where the reply is unknown or dynamic, like when writing an interactive CLI, for example. To help with that, heyredis includes `DynamicReply`, a type that can decode any possible Redis reply.

```zig
const DynamicReply = heyredis.DynamicReply;

const dynReply = try client.sendAlloc(DynamicReply, allocator, .{ "HGETALL", "myhash" });
defer freeReply(dynReply, allocator);

switch (dynReply.data) {
    .Nil, .Bool, .Number, .Double, .Bignum, .String, .List => {},
    .Map => |kvs| {
        for (kvs) |kv| {
            std.debug.warn("[{}] => '{}'\n", kv.key.data.String, kv.value.data.String);
        }
    },
}
```

The code above will print:

```
[banana] => 'yes please'
[price] => '9.99'
```

This is the layout of `DynamicReply`:

```zig
pub const DynamicReply = struct {
    attribs: []KV(DynamicReply, DynamicReply),
    data: Data,

    const Data = union(enum) {
        Nil: void,
        Bool: bool,
        Number: i64,
        Double: f64,
        Bignum: std.math.big.Int,
        String: Verbatim,
        List: []DynamicReply,
        Set: []DynamicReply,
        Map: []KV(DynamicReply, DynamicReply),
    };
};
```
- `.attribs` contains any potential RESP attribute (more on that later)
- `.data` contains a union representing all possible replies.

`KV` is a simple Key-Value struct. It can also be used independently of `DynamicReply`

### Decoding Sorted Set commands WITHSCORES into KV
Calling commands like `ZRANGE` with the `WITHSCORES` option will make Redis reply with a list of couples containing member and score.
`KV` knows how to decode itself from couples (RESP lists of length 2).

```zig
try client.send(void, .{ "ZADD", "sset", "100", "elem1", "200", "elem2" });

const sortSet = try client.sendAlloc([]KV([]u8, f64), allocator, .{ "ZRANGE", "sset", "0", "1", "WITHSCORES" });
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


## RESP attributes
TODO


## TODOS
- Design Zig errors
- Add safety checks when the command is comptime known (e.g. SET takes only 2 arguments)
- Better connection handling (buffering, ...)
- Support for async/await
- Pub/Sub
- Cluster client
- Sentinel client
- Refine the Redis traits
