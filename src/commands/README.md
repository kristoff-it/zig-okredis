# Commands
Commands are a type-checked inteface to send commands to Redis. Conceptually 
they are equivalent to a corresponding sequence of strings that represents an
equivalent of the same command.

Commands also offer an optional validation step that allows the user to get 
extra safety either at comptime or at runtime, depending on what information
the command depends on.

Commands must implement an interface consumed by `serializer.zig`.

## Development notes
This directory contains implementations for all the various commands supported 
by Redis.

Each sub-directory represents a command group just like they are strucuted in 
	[redis.io](https://redis.io/commands).

Elements shared by more than one command of the same group are declared in the 
respective `_utils.zig`.

Elements shared by multiple groups are declared in `_common_utils.zig`.

Shared elements are made available to the user through each group that uses 
them, regardless whether they are unique to the group or in `_common_utils.zig`.

```zig
const Value = okredis.commands.strings.utils.Value;
const Value2 = okredis.commands.hashes.utils.Value;
```

Integration tests with `serializer.zig` are scattered across the various files.
This is the only extraneous dependency outside of this sub-tree and I decided 
that adding it was better than the alternatives. Long story short, I like having 
those tests close to where the command implementation is, they really do depend 
on how the command serializer works, and I  know that `serializer.zig` is never 
going to depend on any of the content in `commands`, so it will never cause a 
circular dependency.