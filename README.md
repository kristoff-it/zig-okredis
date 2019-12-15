
<h1 align="center">OkRedis</h1>
<p align="center">
    <a href="LICENSE"><img src="https://badgen.net/github/license/kristoff-it/zig-heyredis" /></a>
    <a href="https://twitter.com/croloris"><img src="https://badgen.net/badge/twitter/@croloris/1DA1F2?icon&label" /></a>
</p>

<p align="center">
    OkRedis is a zero-allocation client for Redis 6+
</p>

## Handy and Efficient
This client aims to offer an interface with great ergonomics without 
compromising on performance or flexibility: if it makes sense, it's going to be 
straightforward, and if it's possible at all, you're going to be able to do it.


## Zero dynamic allocations, unless explicitly wanted
The client has two main interfaces to send commands: `send` and `sendAlloc`. 
Following Zig's mantra of making dynamic allocations explicit, only `sendAlloc` 
can allocate dynamic memory, and only does so by using a user-provided allocator. 

The way this is achieved is by making good use of RESP3's typed responses and 
Zig's metaprogramming facilities.
The library uses compile-time reflection to specialize down to the parser level, 
allowing heyredis to decode whenever possible a reply directly into a function 
frame, **without any intermediate dynamic allocation**. If you want more 
information about Zig's comptime:
- [Official documentation](https://ziglang.org/documentation/master/#comptime)
- [What is Zig's Comptime?](https://kristoff.it/blog/what-is-zig-comptime) (blog post written by me)

By using `sendAlloc` you can decode replies with arbrirary shape at the cost of 
occasionally performing dynamic allocations. The interface takes an allocator 
as input, so the user can setup custom allocation schemes such as 
[arenas](https://en.wikipedia.org/wiki/Region-based_memory_management).

## Quickstart

```zig
const std = @import("std");
const okredis = @import("./src/okredis.zig");
const SET = okredis.commands.SET;
const OrErr = okredis.OrErr;
const Client = okredis.Client;

pub fn main() !void {
    var client: Client = undefined;
    try client.initIp4("127.0.0.1", 6379);
    defer client.close();

    // Basic interface
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

## Available Documentation
* [Command Builder Interface](#command-builder-interface)
   * [Introduction](#introduction)
   * [Included command builders](#included-command-builders)
   * [Validating command syntax](#validating-command-syntax)
   * [Optimized command builders](#optimized-command-builders)
   * [Creating new command builders](#creating-new-command-builders)
   * [An afterword on command builders vs methods](#an-afterword-on-command-builders-vs-methods)
* [Decoding Redis Replies](#decoding-redis-replies)
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
  * [Bundled Types](#bundled-types)
  * [Decoding Types In The Standard Library](#decoding-types-in-the-standard-library)
  * [Implementing Decodable Types](#implementing-decodable-types)



## TODOS
- Design Zig errors
- Better connection handling (buffering, ...)
- Refine support for async/await
- Pub/Sub
- Refine the Redis traits
