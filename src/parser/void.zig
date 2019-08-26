const std = @import("std");
const fmt = std.fmt;

/// A parser that consumes one full reply and discards it.
/// It's written as a dedicated parser because it doesn't
/// require recursion to consume the right amount of input.
/// Originally this was implemented as a type case inside
/// each t_TYPE parser, but it caused errorset inference
/// to break because of infinite recursion. Additionally,
/// the compiler probably would not make it tail-recursive.
pub const VoidParser = struct {
    pub fn parseVoid(tag: u8, msg: var) !void {
        // When we start, we have one item to consume.
        // As we inspect it we might discover that it's
        // a container and have to increase our items count.
        var itemTag = tag;
        var itemsToConsume: usize = 1;
        while (itemsToConsume > 0) {
            itemsToConsume -= 1;
            switch (itemTag) {
                else => return error.ProtocolError,
                '-', '!' => return error.GotErrorReply,
                '#' => try msg.skipBytes(3), // Bool, e.g. `#t\r\n`
                '$' => {
                    // Lenght-prefixed string
                    // TODO: write real implementation
                    var buf: [100]u8 = undefined;
                    var end: usize = 0;
                    for (buf) |*elem, i| {
                        const ch = try msg.readByte();
                        elem.* = ch;
                        if (ch == '\r') {
                            end = i;
                            break;
                        }
                    }
                    var size = try fmt.parseInt(usize, buf[0..end], 10);
                    try msg.skipBytes(1 + size + 2);
                },
                ':', ',', '+' => {
                    // Simple element with final `\r\n`
                    var ch = try msg.readByte();
                    while (ch != '\n') ch = try msg.readByte();
                },
                '*', '%' => {
                    // Lists and maps
                    var buf: [100]u8 = undefined;
                    var end: usize = 0;
                    for (buf) |*elem, i| {
                        const ch = try msg.readByte();
                        elem.* = ch;
                        if (ch == '\r') {
                            end = i;
                            break;
                        }
                    }
                    try msg.skipBytes(1);
                    std.debug.warn(">>>> {}", buf[0..end]);
                    var size = try fmt.parseInt(usize, buf[0..end], 10);
                    if (tag == '%') size *= 2;
                    itemsToConsume += size;
                },
            }

            // If we still have items to consume, read the tag.
            if (itemsToConsume > 0) itemTag = try msg.readByte();
        }
        return;
    }
};
