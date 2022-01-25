
<h1 align="center">OkRedis</h1>
<p align="center">
    <a href="LICENSE"><img src="https://badgen.net/github/license/kristoff-it/zig-okredis" /></a>
    <a href="https://twitter.com/croloris"><img src="https://badgen.net/badge/twitter/@croloris/1DA1F2?icon&label" /></a>
</p>

<p align="center">
    OkRedis is a zero-allocation client for Redis 6+
</p>

## Handy and Efficient
OkRedis aims to offer an interface with great ergonomics without 
compromising on performance or flexibility.

## Project status
OkRedis is currently in alpha. The main features are mostly complete, but
a lot of polishing is still required.

Everything mentioned in the docs is already implemented and you can just 
`zig run example.zig` to quickly see what it can do. Remember OkRedis only
supports Redis 6 and above.

## Zero dynamic allocations, unless explicitly wanted
The client has two main interfaces to send commands: `send` and `sendAlloc`. 
Following Zig's mantra of making dynamic allocations explicit, only `sendAlloc` 
can allocate dynamic memory, and only does so by using a user-provided allocator. 

The way this is achieved is by making good use of RESP3's typed responses and 
Zig's metaprogramming facilities.
The library uses compile-time reflection to specialize down to the parser level, 
allowing OkRedis to decode whenever possible a reply directly into a function 
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
const SET = okredis.commands.strings.SET;
const OrErr = okredis.types.OrErr;
const Client = okredis.Client;

pub fn main() !void {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 6379);
    var connection = try std.net.tcpConnectToAddress(addr);
    
    var client: Client = undefined;
    try client.init(connection);
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
        .Ok => std.debug.print("success!", .{}),
    }
}
```

## Available Documentation
The reference documentation [is available here](https://kristoff.it/zig-okredis#root).

   * [Using the OkRedis client](CLIENT.md#using-the-okredis-client)
      * [Connecting](CLIENT.md#connecting)
      * [Buffering](CLIENT.md#buffering)
      * [Evented vs blocking I/O](CLIENT.md#evented-vs-blocking-io)
      * [Pipelining](CLIENT.md#pipelining)
      * [Transactions](CLIENT.md#transactions)
      * [Pub/Sub](CLIENT.md#pubsub)

   * [Sending commands](COMMANDS.md#sending-commands)
      * [Base interface](COMMANDS.md#base-interface)
      * [Command builder interface](COMMANDS.md#command-builder-interface)
      * [Validating command syntax](COMMANDS.md#validating-command-syntax)
      * [Optimized command builders](COMMANDS.md#optimized-command-builders)
      * [Creating new command builders](COMMANDS.md#creating-new-command-builders)
      * [An afterword on command builders vs methods](COMMANDS.md#an-afterword-on-command-builders-vs-methods)

   * [Decoding Redis Replies](REPLIES.md#decoding-redis-replies)
      * [Introduction](REPLIES.md#introduction)
      * [The first and second rule of decoding replies](REPLIES.md#the-first-and-second-rule-of-decoding-replies)
      * [Decoding Zig types](REPLIES.md#decoding-zig-types)
         * [Void](REPLIES.md#void)
         * [Numbers](REPLIES.md#numbers)
         * [Optionals](REPLIES.md#optionals)
         * [Strings](REPLIES.md#strings)
         * [Structs](REPLIES.md#structs)
      * [Decoding Redis errors and nil replies as values](REPLIES.md#decoding-redis-errors-and-nil-replies-as-values)
         * [Redis OK replies](REPLIES.md#redis-ok-replies)
      * [Allocating memory dynamically](REPLIES.md#allocating-memory-dynamically)
         * [Allocating strings](REPLIES.md#allocating-strings)
         * [Freeing complex replies](REPLIES.md#freeing-complex-replies)
         * [Allocating Redis Error messages](REPLIES.md#allocating-redis-error-messages)
         * [Allocating structured types](REPLIES.md#allocating-structured-types)
      * [Parsing dynamic replies](REPLIES.md#parsing-dynamic-replies)
      * [Bundled types](REPLIES.md#bundled-types)
      * [Decoding types in the standard library](REPLIES.md#decoding-types-in-the-standard-library)
      * [Implementing decodable types](REPLIES.md#implementing-decodable-types)
         * [Adding types for custom commands (Lua scripts or Redis modules)](REPLIES.md#adding-types-for-custom-commands-lua-scripts-or-redis-modules)
         * [Adding types used by a higher-level language](REPLIES.md#adding-types-used-by-a-higher-level-language)

## Extending OkRedis
If you are a Lua script or Redis module author, you might be interested in 
reading the final sections of `COMMANDS.md` and `REPLIES.md`.

## Embedding OkRedis in a higher level language
Take a look at the final section of `REPLIES.md`.

## TODOS
- Implement remaining command builders
- Better connection management (ipv6, unixsockets, ...)
- Streamline design of Zig errors
- Refine support for async/await and think about connection pooling
- Refine the Redis traits
- Pub/Sub
