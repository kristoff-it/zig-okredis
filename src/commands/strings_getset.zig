// GETSET key value
// const GETSET = struct {
//     key: []const u8,
//     value: Value,

//     const Value = union(enum) {
//         String = []const u8,
//         Int = i64,
//         Float = f64,
//     };

//     pub fn init(key: []const u8, value: Value) GETSET {
//         return .{
//             .key = key,
//             .val = val,
//         };
//     }

//     pub fn validate(self: Self) !void {
//         if (self.key.len == 0) return error.EmptyKeyName;
//     }

//     const Redis = struct {
//         const Command = struct {
//             pub fn serialize(self: GETSET, rootSerializer: type, msg: var) !void {
//                 return rootSerializer.command(msg, .{ "GETSET", self.key, self.value });
//             }
//         };
//     };
// };

// test "example" {
//     const cmd = GETSET.init("lol", "banana");
// }
