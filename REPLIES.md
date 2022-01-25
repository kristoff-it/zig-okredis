# Decoding Redis Replies

## Table of contents
   * [Introduction](#introduction)
   * [The first and second rule of decoding replies](#the-first-and-second-rule-of-decoding-replies)
   * [Decoding Zig types](#decoding-zig-types)
      * [Void](#void)
      * [Numbers](#numbers)
      * [Optionals](#optionals)
      * [Strings](#strings)
      * [Structs](#structs)
   * [Decoding Redis errors and nil replies as values](#decoding-redis-errors-and-nil-replies-as-values)
      * [Redis OK replies](#redis-ok-replies)
   * [Allocating memory dynamically](#allocating-memory-dynamically)
      * [Allocating strings](#allocating-strings)
      * [Freeing complex replies](#freeing-complex-replies)
      * [Allocating Redis Error messages](#allocating-redis-error-messages)
      * [Allocating structured types](#allocating-structured-types)
   * [Parsing dynamic replies](#parsing-dynamic-replies)
   * [Bundled types](#bundled-types)
   * [Decoding types in the standard library](#decoding-types-in-the-standard-library)
   * [Implementing decodable types](#implementing-decodable-types)
      * [Adding types for custom commands (Lua scripts or Redis modules)]( #adding-types-for-custom-commands-lua-scripts-or-redis-modules)
      * [Adding types used by a higher-level language](#adding-types-used-by-a-higher-level-language)

## Introduction
One of the main features of OkRedis is the ability of decoding Redis replies 
without having to resort to dynamic allocations when not stricly necessary.

The main way the user can negotiate reply decoding with the client is via the
first argument of `send` and `sendAlloc`.

Basic example:

```zig
// Send a command and discard the reply
try client.send(void, .{ "SET", "key", "42" });

// Ask for a `i64`
const reply = try client.send(i64, .{ "GET", "key" });
std.debug.print("key = {}\n", .{reply});
```

What's interesting about this example is that Redis replies to the `GET` command 
with a string, but the user is asking for a number, and so the client will try
to parse a number out of the Redis string using `fmt.parseInt`.

As you can see, this is a bit more complex than just 1:1 type mapping, and this
document will try to explain how the client tries to be handy without appearing
too magical.


## The first and second rule of decoding replies
Let's start with the two most important principles of decoding Redis replies.

Redis commands can be considered dynamically typed and, while in practice it's 
easy to know what to expect from a command (by reading the documentation), it's 
possible to get surprised occasionally (especially by thinking you don't need to
read the documentation). This brings us to the first rule:

**Asking for a type that ends up being incompatible with the reply will cause 
the client to return `error.UnsupportedConversion`.** *(Note: error mapping is still WIP so not all errors are being correctly masked for now, so you might momentarily encounter other errors)*

One way in which commands often surprise programmers is by returning errors or 
`nil`. For example calling `INCR` on a non-numeric string will return an error,
and `SET` with the `NX` option will return `nil` when the `NX` condition is not 
satisfied. OkRedis makes sure to never silently drop errors or `nil` replies, 
which brings us to the second rule:

**If the requested type doesn't account for the possiblity of receiving an error
or a `nil` reply, the client will return `error.GotErrorReply` or 
`error.GotNilReply` if any such event occurs.**

Note that encurring in the errors mentioned above will not corrupt the connection. *(Note: this is still WIP, so YMMV)*

Later in this document you will see how to properly decode errors, `nil` replies,
and how to decode replies whose type you can't predict, for example when writing 
an interactive client.


## Decoding Zig types

### Void
By using `void`, we indicate that we're not interested in inspecting the reply, 
so we don't even reserve memory on the stack for it. This will discard any reply 
Redis might send, **except for error and nil replies**, which will reported as
Zig errors, as mentioned in the previous section.

```zig
try client.send(void, .{ "SET", "key", 42 });
```

### Numbers
Numeric replies can be parsed directly to Integer or Float types. If Redis 
replies with a string, the parser will try to parse a number out of it using 
`fmt.parse{Int,Float}` (this is what happens with `GET`).

```zig
const reply = try client.send(i64, .{ "GET", "key" });
```

### Optionals
Optional types let you decode `nil` replies from Redis. When the expected type 
is not an optional, and Redis replies with a `nil`, then `error.GotNilReply` is 
returned instead. 

```zig
try client.send(void, .{ "DEL", "nokey" });
var maybe = try client.send(?i64, .{ "GET", "nokey" });
if (maybe) |val| {
    @panic();
} else {
    // Yep, the value is missing.
}
```

### Strings
Parsing strings without allocating is a bit trickier. It's possible to parse 
a string inside an array, but the two lengths must match, as there is no way to 
otherwise indicate the point up to which the array was filled using an array
type alone (in Zig null-terminated arrays are supported but not the idiomatic
way of representing strings).

For your convenience the library bundles a generic type called `FixBuf(N)`. A 
`FixBuf(N)` just an array of size `N` + a length, so it allows parsing strings 
shorter than `N` by using the length to mark where the string ends. If the 
buffer is not big enough, an error is returned. We will later see how types like 
`FixBuf(N)` can implement custom parsing logic.

```zig
const FixBuf = okredis.types.FixBuf;

try client.send(void, "SET", .{ "hellokey", "Hello World!" });
const hello = try client.send(FixBuf(30), .{ "GET", "hellokey" });

// .toSlice() lets you address the string inside FixBuf
if(std.mem.eql(u8, "Hello World!", hello.toSlice())) { 
    // Yep, the string was parsed
} else {
    @panic();
}

// Alternatively, if the string has a known fixed length (e.g., UUIDs)
const helloArray = try client.send([12]u8, .{ "GET", "hellokey" });
if(std.mem.eql(u8, "Hello World!", helloArray[0..])) { 
    // Yep, the string was parsed
} else {
   @panic();
}
```

### Structs
Map types in Redis (e.g., Hashes, Stream entries) can be decoded as structs.

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
        std.debug.print("{?}", val);
    },
}
```

The code above prints:

```
MyHash{ .banana = src.types.fixbuf.FixBuf(11){ .buf = yes please�, .len = 10 }, .price = 9.98999977e+00 }
```

## Decoding Redis errors and `nil` replies as values
We saw before that receiving an error reply from Redis causes a Zig error: 
`error.GotErrorReply`. This is because the types we tried to decode did not 
account for the possiblity of an error reply. Error replies are just strings 
with a `<ERROR CODE> <error message>` structure (e.g. "ERR unknown command"), 
but are tagged as errors in the underlying protocol. While it would be possible 
to decode them as normal strings, the parser doesn't support that possibility 
for two reasons:

1. Silently decoding errors as strings would make error-checking *error*-prone.
2. Errors should be programmatically inspected only by looking at the code.

To parse error replies OkRedis bundles `OrErr(T)`, a generic type that wraps
your expected return type inside a union. The union has three cases:

- `.Ok` for when the command succeeds, contains `T`
- `.Err` for when the reply is an error, contains the error code
- `.Nil` for when the reply is `nil`

The last case is there just for convenience, as it's basically equivalent to 
making the expected return type an optional. Adding `.Nil` basically makes 
`OrErr` your one-stop-shop for error checking.

**In general it's a good idea to wrap most reply types with `OrErr`.**

```zig
const FixBuf = okredis.types.FixBuf;
const OrErr = okredis.types.OrErr;

try client.send(void, .{ "SET", "stringkey", "banana" });

// Success
switch (try client.send(OrErr(FixBuf(100)), .{ "GET", "stringkey" })) {
    .Err, .Nil => @panic(),
    .Ok => |reply| std.debug.print("stringkey = {s}\n", reply.toSlice()),
}

// Error
switch (try client.send(OrErr(i64), .{ "INCR", "stringkey" })) {
    .Ok, .Nil => @panic(),
    .Err => |err| std.debug.print("error code = {s}\n", err.getCode()),
}
```

### Redis OK replies
`OrErr(void)` is a good way of parsing `OK` replies from Redis in case you want 
to inspect error codes. 

## Allocating memory dynamically

The examples above perform zero allocations but consequently make it awkward to 
work with strings. Using `sendAlloc` you can allocate dynamic memory every time 
the reply type is a pointer or a slice.

### Allocating strings

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

The previous examples produced types that are easy to free. Later we will see 
more complex examples where it becomes tedious to free everything by hand. For 
this reason OkRedis includes `freeReply`, which frees recursively a value 
produced by `sendAlloc`. The following examples will showcase how to use it.

```zig
const freeReply = okredis.freeReply;
```

### Allocating Redis Error messages

When using `OrErr`, we were only saving the error code and throwing away the 
message. Using `OrFullErr` you will also be able to inspect the full error 
message. The error code doesn't need to be freed (it's written to a FixBuf), 
but the error message will need to be freed.

```zig
const OrFullErr = okredis.types.OrFullErr;

var incrErr = try client.sendAlloc(OrFullErr(i64), allocator, .{ "INCR", "divine" });
defer freeReply(incErr, allocator);

switch (incrErr) {
    .Ok, .Nil => @panic(),
    .Err => |err| {
        // This is where alternatively you would perform manual deallocation: 
        // defer allocator.free(err.message)
        std.debug.print("error code = '{s}'\n", err.getCode());
        std.debug.print("error message = '{s}'\n", err.message);
    },
}
```

The code above will print:

```
error code = 'ERR' 
error message = 'value is not an integer or out of range'
```

### Allocating structured types

Previously when we wanted to decode a struct we had to use a `FixBuf` to decode 
a `[]u8` field. Now we can just do it the normal way.

```zig
const MyDynHash = struct {
    banana: []u8,
    price: f32,
};

const dynHash = try client.sendAlloc(OrErr(MyDynHash), allocator, .{ "HGETALL", "myhash" });
defer freeReply(dynHash, allocator);

switch (dynHash) {
    .Nil, .Err => unreachable,
    .Ok => |val| std.debug.print("{?}", val),
}
```

The code above will print:

```
MyDynHash{ .banana = yes please, .price = 9.98999977e+00 }
```

It's also possible to use `OrErr(*MyDynHash)` to have the client allocate on the 
heap the decoded reply, in case we plan to have the value survive longer than 
the function's lifetime.

## Parsing dynamic replies

While most programs will use simple Redis commands and will know the shape of 
the reply, one might also be in a situation where the reply is unknown or 
dynamic, like when writing an interactive CLI, for example. To help with that, 
OkRedis includes `DynamicReply`, a type that can be decoded as any possible 
Redis reply.

```zig
const DynamicReply = okredis.types.DynamicReply;

const dynReply = try client.sendAlloc(DynamicReply, allocator, .{ "HGETALL", "myhash" });
defer freeReply(dynReply, allocator);

switch (dynReply.data) {
    .Nil, .Bool, .Number, .Double, .Bignum, .String, .List => {},
    .Map => |kvs| {
        for (kvs) |kv| {
            std.debug.print("[{s}] => '{s}'\n", kv.key.data.String, kv.value.data.String);
        }
    },
}
```

The code above will print:

```
[banana] => 'yes please'
[price] => '9.99'
```

## Bundled types
For a full list of the types bundled with OkRedis, read 
[the documentation](https://kristoff.it/zig-okredis#root).

## Decoding types in the standard library
TODO

## Implementing decodable types
The custom decodable types included in OkRedis should be enough for most users,
but it's possible that in special cases one might want to decode a complex type
using the parser's facilities to avoid intermediate representations.

Two main cases for this need could be:
1. Redis module ([or Lua script](https://redis.io/commands/eval#using-lua-scripting-in-resp3-mode)) authors that want to offer client-side tools to their users
2. Somebody who might want to embed OkRedis in a higher-level language via the C ABI.

Let's expand slightly on these two use cases.

### Adding types for custom commands (Lua scripts or Redis modules)
If you're adding a command to Redis (or implementing a Lua script) that has a 
complex response type, it might make sense to provide a boiler-plate type for to
your users.

In this case you are probably fine by simply defining a struct that properly 
represents the fixed parts of your responses.

```zig
// If replies are complex, but with a static structure.
const MyCommandReplyType = struct {
    id: []u8,
    query_exec_time: u64,
    results: []Result,

    pub const Result = struct {
        partition_id: usize,
        result: []u8,
    };
};

// Usage is straightforward as usual.
_ = try client.sendAlloc(MyCommandReplyType, allocator, .{"CUSTOM_COMMAND"});

// And the user will still be able to combine the type.
_ = try client.sendAlloc(OrErr(MyCommandReplyType), allocator, .{"CUSTOM_COMMAND"});


// Some types might be best defined as generic to let the user customize it.
// The following type is a reasonable way of decoding a Redis stream entry 
// letting the user provide a type that decodes the entry's contents, 
// for example.
pub fn StreamEntry(comptime T: type) type {
    return struct {
        id: []u8,
        data: T,
    };
}

// Continuing with the Redis streams example, the user might then do some
// composition based on their needs.
const Measurement = struct {
    temperature: f64,
    sensor_id: []u8,
    room_name: []u8,
};

const ReadMeasurements = struct {
    stream1: []StreamEntry(Measurement),
    stream2: []StreamEntry(Measurement),
    @"stream-remote": []StreamEntry(Measurement),
};

_ = try client.sendAlloc(ReadMeasurements, allocator, XREAD.init(.NoCount, .NoBlock, &[_][]const u8{
    "stream1",
    "stream2",
    "stream-remote",
}));

```

### Adding types used by a higher-level language
Let's say that you want to embed OkRedis in Python using Python's CFFI 
faclities. In that case you'd want to have the parser produce directly custom
`PyObject` instances. 

In this case you will probably have to deal more closely with the parsing 
process. I recommend to read the implementation of 
[`DynamicReply`](src/types/reply.zig) 
which does 90% of what you would need to do.

Zig will be able to provide the remaining tools you will need through it's C 
ABI interoperability features. As an example you will probably want to define 
your custom `PyObject`-like structs as 
[`extern`](https://ziglang.org/documentation/master/#toc-extern-struct).