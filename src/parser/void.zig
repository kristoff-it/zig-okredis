const std = @import("std");
const Reader = std.Io.Reader;
const fmt = std.fmt;

/// A parser that consumes one full reply and discards it. It's written as a
/// dedicated parser because it doesn't require recursion to consume the right
/// amount of input and, given the fact that the type doesn't "peel away",
/// recursion would look unbounded to the type system.
/// It can also be used to consume just one attribute element by claiming to
/// have found a map instead. This trick is used by the root parser in the
/// initial setup of both `parse` and `parseAlloc`.
pub const VoidParser = struct {
    pub fn discardOne(tag: u8, r: *Reader) !void {
        // When we start, we have one item to consume.
        // As we inspect it, we might discover that it's a container, requiring
        // us to increase our items count.
        var err_found = false;

        var current_tag = tag;
        var items_left: usize = 1;
        while (items_left > 0) {
            items_left -= 1;
            switch (current_tag) {
                else => std.debug.panic("Found `{c}` in the *VOID* parser's switch." ++
                    " Probably a bug in a type that implements `Redis.Parser`.", .{current_tag}),
                '_' => try r.discardAll(2), // `_\r\n`
                '#' => try r.discardAll(3), // `#t\r\n`, `#t\r\n`
                '$', '=', '!' => {
                    // Lenght-prefixed string
                    if (current_tag == '!') {
                        err_found = true;
                    }

                    const digits = try r.takeSentinel('\r');
                    const size = try fmt.parseInt(usize, digits, 10);
                    try r.discardAll(1 + size + 2); // \n, item, \r\n
                },
                ':', ',', '+', '-' => {
                    // Simple element with final `\r\n`
                    if (current_tag == '-') {
                        err_found = true;
                    }
                    _ = try r.discardDelimiterInclusive('\n');
                },
                '|' => {
                    // Attributes are metadata that precedes a proper reply
                    // item and do not count towards the original
                    // `itemsToConsume` count. Consume the attribute element
                    // without counting the current item as consumed.

                    const digits = try r.takeSentinel('\r');
                    var size = try fmt.parseInt(usize, digits, 10);
                    try r.discardAll(1);
                    size *= 2;

                    // Add all the new items to the pile that needs to be
                    // consumed, plus the one that we did not consume this
                    // loop.
                    items_left += size + 1;
                },
                '*', '%' => {
                    // Lists, Maps
                    const digits = try r.takeSentinel('\r');
                    var size = try fmt.parseInt(usize, digits, 10);
                    try r.discardAll(1);

                    // Maps advertize the number of field-value pairs.
                    if (current_tag == '%') size *= 2;
                    items_left += size;
                },
            }

            // If we still have items to consume, read the next tag.
            if (items_left > 0) current_tag = try r.takeByte();
        }
        if (err_found) return error.GotErrorReply;
    }
};
