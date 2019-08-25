/// A type that knows how to decode itself form a RESP3 stream.
/// It's expected to implement three functions:
///
/// fn parse(tag: u8, comptime rootParser: type, msg: var) !Self
/// fn parseAlloc(tag: u8, comptime rootParser: type, allocator: *Allocator, msg: var) !Self
/// fn destroy(self: Self, comptime rootParser: type, allocator: *Allocator) void
///
/// `rootParser` is a reference to the RESP3Parser, which contains the
/// main parsing logic. It's passed to the type in order to be able to
/// recursively reuse the logic already implemented. For example, the
/// KV type uses it to parse both `key` and `value` fields.
///
/// `msg` is an InStream attached to a Redis connection.
///
/// In case of failure the parsing function is NOT required to consume
/// the proper amount of stream data. It's expected that decoding errors
/// always result in a broken connection state.
pub fn isParserType(comptime T: type) bool {
    const tid = @typeId(T);
    if ((tid == .Struct or tid == .Enum or tid == .Union) and
        @hasDecl(T, "Redis") and @hasDecl(T.Redis, "Parser"))
    {
        if (!@hasDecl(T.Redis.Parser, "parse"))
            @compileError(
                \\`Redis.Parser` trait requires implementing:
                \\    fn parse(tag: u8, comptime rootParser: type, msg: var) !Self
                \\
            );

        if (!@hasDecl(T.Redis.Parser, "parseAlloc"))
            @compileError(
                \\`Redis.Parser` trait requires implementing:
                \\    fn parseAlloc(tag: u8, comptime rootParser: type, allocator: *Allocator, msg: var) !Self
                \\
            );

        if (!@hasDecl(T.Redis.Parser, "destroy"))
            @compileError(
                \\`Redis.Parser` trait requires implementing:
                \\    fn destroy(self: Self, comptime rootParser: type, allocator: *Allocator) void
                \\
            );

        return true;
    }
    return false;
}

/// A type that knows how to serialize itself as one or more arguments
/// to a Redis command. The RESP3 protocol is used in a asymmetrical way
/// by Redis, so this is NOT the inverse operation of parsing.
/// As an example, a struct might implement decoding from a RESP Map, but
/// the correct way of serializing itself would be as a FLAT sequence of
/// field-value pairs, to be used with XADD or HMSET:
///    HMSET mystruct field1 val1 field2 val2 ...
pub fn isArgType(comptime T: type) bool {
    const tid = @typeId(T);
    return (tid == .Struct or tid == .Enum or tid == .Union) and
        @hasDecl(T, "Redis") and @hasDecl(T.Redis, "ArgSerializer");
}

// test "trait error message" {
//     const T = struct {
//         pub const Redis = struct {
//             pub const Parser = struct {};
//         };
//     };

//     _ = isParserType(T);
// }