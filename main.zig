const std = @import("std");
const Client = @import("./client.zig").Client;
const OrErr = @import("./types/error_reply.zig").OrErr;
const FixBuf = @import("./types/string_buffer.zig").RedisStringBuffer;

pub fn main() !void {
    // Connect
    var client = try Client.initIp4("127.0.0.1", 6379);

    // Send a command, don't care about reply
    // (but it will error out if redis returns an error response)
    try client.send(void, "SET key 42");

    // Get key, return i64 (note that the reply is a redis string)
    const reply = try client.send(i64, "GET key");
    std.debug.warn("banana = {}\n", reply);

    // Send bad command, this time we are interested in the error code
    switch (try client.send(OrErr(void), "OHNO")) {
        .Ok, .Nil => unreachable,
        .Err => |err| std.debug.warn("error code = {}\n", err.getCode()),
    }

    const MyHash = struct {
        banana: FixBuf(10),
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
}
