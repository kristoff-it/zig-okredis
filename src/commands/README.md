This directory contains implementations for all the various commands supported 
by Redis.

Each sub-directory represents a command group just like they are strucuted in 
	[redis.io](https://redis.io/commands).

Elements shared by more than one command of the same group are declared in the 
respective `_utils.zig`.

Elements shared by multiple groups are declared in `_common_utils.zig`.

Integration tests with `serializer.zig` are scattered across the various files.
This is the only dependency outside of this sub-tree and I decided that adding 
this extraneous dependency was better than the alternatives. Long story short, 
I like having those tests close to where the command implementation is, they 
really do depend on how the command serializer works, and I  know that 
`serializer.zig` is never going to depend on any of the content in `commands`, 
so it will never cause a circular dependency.