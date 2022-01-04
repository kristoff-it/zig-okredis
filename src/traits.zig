/// A type that knows how to decode itself form a RESP3 stream.
/// It's expected to implement three functions:
/// ```
/// fn parse(tag: u8, comptime rootParser: type, msg: var) !Self
/// fn parseAlloc(tag: u8, comptime rootParser: type, allocator: Allocator, msg: var) !Self
/// fn destroy(self: Self, comptime rootParser: type, allocator: Allocator) void
/// ```
/// `rootParser` is a reference to the RESP3Parser, which contains the main
/// parsing logic. It's passed to the type in order to allow it  to recursively
/// reuse the logic already implemented. For example, the KV type uses it to
/// parse both `key` and `value` fields.
///
/// `msg` is an InStream attached to a Redis connection.
///
/// In case of failure the parsing function is NOT required to consume the
/// proper amount of stream data. It's expected that decoding errors always
/// result in a broken connection state.
pub fn isParserType(comptime T: type) bool {
    const tid = @typeInfo(T);
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
                \\    fn parseAlloc(tag: u8, comptime rootParser: type, allocator: Allocator, msg: var) !Self
                \\
            );

        if (!@hasDecl(T.Redis.Parser, "destroy"))
            @compileError(
                \\`Redis.Parser` trait requires implementing:
                \\    fn destroy(self: *Self, comptime rootParser: type, allocator: Allocator) void
                \\
            );

        return true;
    }
    return false;
}

/// A type that wants access to attributes because intends to decode them.
/// When the declaration is missing or returns false, attributes are discarded
/// from the stream automatically by the main parser.
pub fn handlesAttributes(comptime T: type) bool {
    if (comptime isParserType(T)) {
        if (@hasDecl(T.Redis.Parser, "HandlesAttributes")) {
            return T.Redis.Parser.HandlesAttributes;
        }
    }
    return false;
}

/// A type that doesn't want to be wrapped directly in an optional because
/// it would have ill-formed / unclear semantics. An example of this are
/// types that read attributes. For those types this trait defaults to `true`
pub fn noOptionalWrapper(comptime T: type) bool {
    if (comptime isParserType(T)) {
        if (@hasDecl(T.Redis.Parser, "NoOptionalWrapper")) {
            return T.Redis.Parser.NoOptionalWrapper;
        } else {
            if (@hasDecl(T.Redis.Parser, "HandlesAttributes")) {
                return T.Redis.Parser.HandlesAttributes;
            }
        }
    }
    return false;
}

/// A type that knows how to serialize itself as one or more arguments to a
/// Redis command. The RESP3 protocol is used in a asymmetrical way by Redis,
/// so this is NOT the inverse operation of parsing. As an example, a struct
/// might implement decoding from a RESP Map, but the correct way of
/// serializing itself would be as a FLAT sequence of field-value pairs, to be
/// used with XADD or HMSET:
///     HMSET mystruct field1 val1 field2 val2 ...
pub fn isArguments(comptime T: type) bool {
    const tid = @typeInfo(T);
    return (tid == .Struct or tid == .Enum or tid == .Union) and @hasDecl(T, "RedisArguments");
}

pub fn isCommand(comptime T: type) bool {
    const tid = @typeInfo(T);
    return (tid == .Struct or tid == .Enum or tid == .Union) and @hasDecl(T, "RedisCommand");
}
// test "trait error message" {
//     const T = struct {
//         pub const Redis = struct {
//             pub const Parser = struct {};
//         };
//     };

//     _ = isParserType(T);
// }

test "docs" {
    @import("std").testing.refAllDecls(@This());
}
