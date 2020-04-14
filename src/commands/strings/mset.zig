// // MSET key value [key value ...]

// pub const MSET = struct {
//     kvs: []const KV,

//     const Self = @This();
//     pub fn init(kvs: []const KV) Self {
//         return .{ .keys = keys };
//     }

//     pub fn validate(self: Self) !void {
//         if (self.kvs.len == 0) return error.KVsArrayIsEmpty;
//         for (self.kvs) |kv| {
//             if (kv.key.len == 0) return error.EmptyKeyName;
//         }
//     }

//     const Redis = struct {
//         const Command = struct {
//             pub fn serialize(self: Self, rootSerializer: type, msg: var) !void {
//                 return rootSerializer.serialize(msg, .{ "MSET", self.kvs });
//             }
//         };
//     };
// };

// test "basic usage" {
//     const cmd = MSET.init(.{ "lol", "123", "test" });
// }
