# Keys
This is an OOP interface to commands.
Instead of the command itself being the focus, the key type is the core, and 
commands are behaviour attached to it.

This interface is still data-driven, meaning that the various methods produce 
command instances and don't actually do any side-effect. The reason for this 
choice is the same as for the rest of this client design: I want to make it 
obvious when network communication is happening and I don't want to make it 
ambiguous when pipelining is happening or not.

## Usage example


```zig
const Stream = okredis.keys.Stream;

const temps = Stream.init("temperatures");

_ = try client.pipeAlloc(OrErr([]u8), allocator, .{
	temps.xadd("*", ["temperature", "123", "humidity": "10"]),
	temps.xadd("*", ["temperature", "321", "humidity": "1"]),
});

const MyTemps = struct {
	temperature: float64,
	humidity: float64,
};

const cmd = temps.xreadStruct(MyTemps, 10, .NoBlock, "123-123");
_ = try client.sendAlloc(cmd.Reply, cmd);

// Even better
_ = try client.sendAlloc(OrErr(cmd.Reply), cmd);

```

## Development notes

Keys depend on commands as they are basically only syntax sugar built on top of 
them.

Internally, all key types depend on the `Key` type in `key.zig` as a way to 
offer generic key operations.

```zig
const Stream = okredis.keys.Stream;

// Creates a stream key instance and then creates a command to delete it.
const temps = Stream.init("temperatures");
const cmd = temps.key.del();
```
