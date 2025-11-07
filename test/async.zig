const std = @import("std");
const Io = std.Io;

const okredis = @import("../src/root.zig");
const Client = okredis.Client;

const gpa = std.heap.smp_allocator;
pub fn main() !void {

    // Pick your preferred Io implementation.
    var threaded: Io.Threaded = .init(gpa);
    defer threaded.deinit();
    const io = threaded.io();

    // Open a TCP connection.
    // NOTE: managing the connection is your responsibility.
    const addr: Io.net.IpAddress = try .parseIp4("127.0.0.1", 6379);
    const connection = try addr.connect(io, .{ .mode = .stream });
    defer connection.close(io);

    var rbuf: [1024]u8 = undefined;
    var wbuf: [1024]u8 = undefined;
    var reader = connection.reader(io, &rbuf);
    var writer = connection.writer(io, &wbuf);

    // The last argument are auth credentials.
    var client = try Client.init(io, &reader.interface, &writer.interface, null);

    var rand: std.Random.DefaultPrng = .init(6379);
    var g: Io.Group = .init;
    // for (0..1) |i| {
    for (0..try std.Thread.getCpuCount()) |i| {
        g.async(io, countdown, .{ &client, i, rand.random().int(u16) });
    }

    g.wait(io);
}

fn countdown(client: *Client, i: usize, num: u32) void {
    countdownFallible(client, i, num) catch |err| {
        std.debug.panic("[{}] error: {t}", .{ i, err });
    };
}

fn countdownFallible(client: *Client, i: usize, n: u32) !void {
    var num = n;
    const key = try std.fmt.allocPrint(gpa, "coro-{}", .{i});
    try client.send(void, .{ "SET", key, num });
    while (num > 0) {
        const value = try client.send(u32, .{ "INCRBY", key, -1 });
        // std.debug.print("[{}] {}\n", .{ i, value });
        num -= 1;
        if (value != num) @panic("mismatch!");
    }
    std.log.info("[{}] correct countdown from {}", .{ i, n });
}
