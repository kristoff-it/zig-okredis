# Command Builder Interface


## Intro
The main way of sending commands using OkRedis is to just use an argument list
or an array:

```zig
// Using an argument list
client.send(void, .{ "SET", "key", 42 });

// Using an array
const cmd = [_][]const u8{ "SET", "key", "42" };
client.send(void, &cmd);
```

While simple and straightforward, this approach is prone to errors, as users 
might introduce typos or write a command that is syntactically wrong without any
warning at comptime.

Because of that, some other Redis clients consider such interface a fallback 
(or "escape hatch") that allows users to send commands that the library doesn't 
support, while the main usage looks like this:

```python
# Python example
client.xadd("key", "*", {"field1": "value1", "field2": 42})
client.set("fruit", "banana")
```

OkRedis doesn't provide any command-specific method and instead uses a different
approach based on the idea of command builders. It might feel annoying at first
to have to deal with a different approach, but I'll show in this document how 
this pattern brings enough advantages to the table to make the switch well worth.

## Included Command Builders
OkRedis includes command builders for all the basic Redis commands.
All commands are grouped by the type of key they operate on (e.g., `strings`, 
`hashes`, `streams`), in the same way they are grouped on 
[https://redis.io/commands](https://redis.io/commands).

Usage example:
```zig
const okredis = @import("./src/okredis.zig");
const cmds = okredis.commands;

pub fn main() !void {
    var client: Client = undefined;
    try client.initIp4("127.0.0.1", 6379);
    defer client.close();

    // SET key 42 NX
    try client.send(void, cmds.strings.SET.init("key", 42, .NoExpire, .IfNotExisting));

    // GET key
    _ = try client.send(i64, cmds.strings.GET.init("key"));
}
```

For the full list of available command builders consult 
[the documentation](https://kristoff.it/zig-okredis/).

## Validating Command Syntax
The `init` function of each type helps ensuring the command is properly formed,
but some commands have constraints that can't be enforced via a function 
signature, or that are relatively expensive to check.
For this reason all command builders have a `validate` method that can be used
to apply syntax checks. 

**In other words, `init` will allow users to create invalid commands, and it's 
the user's responsibility to use `validate` when appropriate.**

Usage example:

```zig
// FV is a type that represents Field-Value pairs.
const FV = okredis.types.FV;
const fields = &[_]FV{ .{.field = "field1", .value = "value1"} };


// Case 1: well-formed command
var readCmd1 = cmds.streams.XADD.init("stream-key", "*", fields);
try readCmd1.validate(); // Validation will succeed


// Case 2: invalid ID
var readCmd2 = cmds.streams.XADD.init("stream-key", "INVALID_ID", fields);
try readCmd2.validate(); // -> error.InvalidID

```

Validation of a command that doesn't depend on runtime values can be performed 
at comptime:

```zig
comptime readCmd.validate() catch unreachable;
```

With the command builder interface it's easier to let the user choose whether
to apply validation or not, and when (comptime vs runtime). Using a method-based
interface we would lose many of those options.

## Optimized Command Builders
Some command builders implement commands that deal with struct-shaped data.
Two notable examples are `HSET` and `XADD`.
In the previous example we saw how `commands.streams.XADD` takes a slice of `FV`
pairs, but it would be convinient to be able to use a struct to convey the same
request in a more precise (and optimized) way.

To answer this need, some command builders offer a `forStruct` function that
can be used to create a specialized version of the command builder:

```zig
const Person = struct {
    name: []const u8,
    age: u64,
};

// This creates a new type.
const XADDPerson = cmds.streams.XADD.forStruct(Person);

// This is an instance of a command.
const xadd_loris = XADDPerson.init("people-stream", "*", .{
    .name = "loris",
    .age = 29,
});
```

## Creating New Command Builders
Another advantage of command builders is the possibility of adding new commands 
to the ones that are included in OkRedis.
While in some languages it's trivial to monkey patch new methods onto a 
pre-existing class, in others it's either not possible or the avaliable means
have other types of issues and limitations (e.g., extension methods). 

**Creators of Redis modules might want to provide their users with client-side 
tooling for their module and this approach makes module commands feel as native
as the built-in ones.**

OkRedis uses two traits to delegate serialization to a struct that implements
a command: `RedisCommand` and `RedisArguments`.

For now I recommend reading the source code of existing commands to get an idea
of how they works, possibly starting with simple commands (e.g., avoid staring 
with `SET` as the many options make it unexpectedly complex).