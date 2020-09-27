const std = @import("std");
const fmt = std.fmt;

/// A parser that consumes one full reply and discards it. It's written as a
/// dedicated parser because it doesn't require recursion to consume the right
/// amount of input and, given the fact that the type doesn't "peel away",
/// recursion would look unbounded to the type system.
/// It can also be used to consume just one attribute element by claiming to
/// have found a map instead. This trick is used by the root parser in the
/// initial setup of both `parse` and `parseAlloc`.
pub const VoidParser = struct {
    pub fn discardOne(tag: u8, msg: anytype) !void {
        // When we start, we have one item to consume.
        // As we inspect it, we might discover that it's a container, requiring
        // us to increase our items count.
        var foundError = false;

        var itemTag = tag;
        var itemsToConsume: usize = 1;
        while (itemsToConsume > 0) {
            itemsToConsume -= 1;
            switch (itemTag) {
                else => std.debug.panic("Found `{c}` in the *VOID* parser's switch." ++
                    " Probably a bug in a type that implements `Redis.Parser`.", .{itemTag}),
                '_' => try msg.skipBytes(2, .{}), // `_\r\n`
                '#' => try msg.skipBytes(3, .{}), // `#t\r\n`, `#t\r\n`
                '$', '=', '!' => {
                    // Lenght-prefixed string
                    if (itemTag == '!') {
                        foundError = true;
                    }

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
                    try msg.skipBytes(1 + size + 2, .{});
                },
                ':', ',', '+', '-' => {
                    // Simple element with final `\r\n`
                    if (itemTag == '-') {
                        foundError = true;
                    }
                    var ch = try msg.readByte();
                    while (ch != '\n') ch = try msg.readByte();
                },
                '|' => {
                    // Attributes are metadata that precedes a proper reply
                    // item and do not count towards the original
                    // `itemsToConsume` count. Consume the attribute element
                    // without counting the current item as consumed.

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
                    try msg.skipBytes(1, .{});
                    var size = try fmt.parseInt(usize, buf[0..end], 10);
                    size *= 2;

                    // Add all the new items to the pile that needs to be
                    // consumed, plus the one that we did not consume this
                    // loop.
                    itemsToConsume += size + 1;
                },
                '*', '%' => {
                    // Lists, Maps
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
                    try msg.skipBytes(1, .{});
                    var size = try fmt.parseInt(usize, buf[0..end], 10);

                    // Maps advertize the number of field-value pairs,
                    // so we double the amount in that case.
                    if (tag == '%') size *= 2;
                    itemsToConsume += size;
                },
            }

            // If we still have items to consume, read the next tag.
            if (itemsToConsume > 0) itemTag = try msg.readByte();
        }
        if (foundError) return error.GotErrorReply;
    }
};
