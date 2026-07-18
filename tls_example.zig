const std = @import("std");
const Io = std.Io;
const tls = std.crypto.tls;
const Certificate = std.crypto.Certificate;

const okredis = @import("okredis");
const Client = okredis.Client;

// Each TLS buffer must be able to hold at least one full TLS record.
const tls_buf_len = tls.max_ciphertext_record_len;

// Small env-var helper (this example links libc for `getenv`; a real app would
// read configuration however it prefers).
fn getEnv(name: [:0]const u8) ?[]const u8 {
    return std.mem.span(std.c.getenv(name) orelse return null);
}

// --- The one piece TLS needs that a plain socket doesn't ---------------------
//
// okredis is bring-your-own-stream: `Client.init` takes an `Io.Reader` + an
// `Io.Writer`, and after buffering a command it calls `writer.flush()`.
//
// Over a plain TCP socket that is enough: the socket writer's `flush` puts the
// bytes on the wire. Over TLS it is NOT: `std.crypto.tls.Client.writer.flush()`
// only *encrypts* the plaintext into the underlying transport writer's buffer -
// it does not flush the transport. So a naive
// `Client.init(io, &tls.reader, &tls.writer, ...)` writes HELLO, "flushes" it
// into the socket buffer, and then blocks forever waiting for a reply the
// server never received.
//
// `TlsTransport` is a tiny `Io.Writer` that closes that gap: on drain/flush it
// encrypts through the TLS writer AND flushes the underlying socket, so okredis
// can drive it exactly like a plain socket. (If okredis grew an optional
// "flush the transport too" hook, this shim would go away.)
const TlsTransport = struct {
    tls: *tls.Client,
    sock: *Io.Writer,
    writer: Io.Writer,

    const vtable: Io.Writer.VTable = .{ .drain = drain };

    fn init(tls_client: *tls.Client, sock: *Io.Writer, buffer: []u8) TlsTransport {
        return .{
            .tls = tls_client,
            .sock = sock,
            .writer = .{ .buffer = buffer, .vtable = &vtable },
        };
    }

    fn drain(w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const self: *TlsTransport = @fieldParentPtr("writer", w);
        const tw = &self.tls.writer;

        var total: usize = 0;
        const buffered = w.buffered();
        if (buffered.len != 0) {
            try tw.writeAll(buffered);
            total += buffered.len;
        }
        for (data[0 .. data.len - 1]) |bytes| {
            try tw.writeAll(bytes);
            total += bytes.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| {
            try tw.writeAll(last);
            total += last.len;
        }

        try tw.flush(); // encrypt plaintext into the socket writer's buffer
        try self.sock.flush(); // push the ciphertext onto the wire
        return w.consume(total);
    }
};

// Connecting to a `rediss://` endpoint (AWS ElastiCache/Valkey, Upstash, Redis
// Cloud, ...) is just "wrap std.crypto.tls around the socket and hand okredis
// the decrypted stream".
//
//   Managed Redis (publicly-trusted cert):
//     REDIS_HOST=my-cache.abc123.serverless.usw2.cache.amazonaws.com \
//     REDIS_ADDR=<resolved ip> REDIS_PORT=6379 REDIS_PASS=... \
//     zig build run-tls-example
//
//   Dev server with a self-signed cert (relaxes verification):
//     REDIS_TLS_INSECURE=1 REDIS_ADDR=127.0.0.1 REDIS_PORT=6380 \
//     zig build run-tls-example
pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    var threaded: Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // --- configuration (points at a rediss:// endpoint) ---
    // `host` is used for TLS SNI + certificate hostname verification. We connect
    // to `REDIS_ADDR` (a literal IPv4 here for brevity - resolving a hostname to
    // an address is the caller's job, same as in the non-TLS example).
    const host = getEnv("REDIS_HOST") orelse "localhost";
    const ip = getEnv("REDIS_ADDR") orelse "127.0.0.1";
    const port: u16 = if (getEnv("REDIS_PORT")) |p|
        try std.fmt.parseInt(u16, p, 10)
    else
        6379;
    // Leave unset for managed Redis: the server presents a publicly-trusted cert
    // that we verify against the system root store, with hostname verification.
    // Set REDIS_TLS_INSECURE=1 to talk to a dev server using a self-signed cert.
    const insecure = getEnv("REDIS_TLS_INSECURE") != null;

    // --- plain TCP connection (managing it is your responsibility) ---
    const addr: Io.net.IpAddress = try .parseIp4(ip, port);
    const conn = try addr.connect(io, .{ .mode = .stream });
    defer conn.close(io);

    // Socket-side buffers carry encrypted bytes; each must hold a full TLS record.
    var sock_rbuf: [tls_buf_len]u8 = undefined;
    var sock_wbuf: [tls_buf_len]u8 = undefined;
    var sock_reader = conn.reader(io, &sock_rbuf);
    var sock_writer = conn.writer(io, &sock_wbuf);

    // TLS-side buffers carry the plaintext that okredis reads/writes.
    var tls_rbuf: [tls_buf_len]u8 = undefined;
    var tls_wbuf: [tls_buf_len]u8 = undefined;

    var entropy: [tls.Client.Options.entropy_len]u8 = undefined;
    io.random(&entropy);
    const now = Io.Clock.real.now(io);

    // System root CA bundle (only used when verifying a real server cert).
    var ca_bundle: Certificate.Bundle = .empty;
    defer ca_bundle.deinit(gpa);
    var ca_lock: Io.RwLock = .init;
    if (!insecure) try ca_bundle.rescan(gpa, io, now);

    // Perform the TLS handshake over the raw socket reader/writer.
    var tls_client = try tls.Client.init(
        &sock_reader.interface,
        &sock_writer.interface,
        .{
            .host = if (insecure) .no_verification else .{ .explicit = host },
            .ca = if (insecure) .self_signed else .{ .bundle = .{
                .gpa = gpa,
                .io = io,
                .lock = &ca_lock,
                .bundle = &ca_bundle,
            } },
            .read_buffer = &tls_rbuf,
            .write_buffer = &tls_wbuf,
            .entropy = &entropy,
            .realtime_now = now,
        },
    );

    // Wrap the TLS writer so that okredis's `flush()` also flushes the socket.
    var xport_buf: [tls_buf_len]u8 = undefined;
    var transport = TlsTransport.init(&tls_client, &sock_writer.interface, &xport_buf);

    // Optional AUTH (managed Redis usually requires a password / ACL user).
    const auth: ?Client.Auth = if (getEnv("REDIS_PASS")) |pass|
        .{ .user = getEnv("REDIS_USER"), .pass = pass }
    else
        null;

    // Hand okredis the decrypted TLS reader and the transport-flushing writer.
    // Everything else (RESP3, pipelining, typed replies) works unchanged.
    var client = try Client.init(io, &tls_client.reader, &transport.writer, auth);

    try client.send(void, .{"PING"});
    try client.send(void, .{ "SET", "okredis:tls", "hello over TLS" });

    const reply = try client.send(okredis.types.FixBuf(64), .{ "GET", "okredis:tls" });
    std.debug.print("GET okredis:tls => {s}\n", .{reply.toSlice()});
}
