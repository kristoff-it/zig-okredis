// GEODIST key member1 member2 [m|km|ft|mi]

const Unit = @import("./_utils.zig").Unit;

pub const GEODIST = struct {
    key: []const u8,
    member1: []const u8,
    member2: []const u8,
    unit: Unit = .meters,

    pub fn init(key: []const u8, member1: []const u8, member2: []const u8, unit: Unit) GEODIST {
        return .{ .key = key, .member1 = member1, .member2 = member2, .unit = unit };
    }

    pub fn validate(self: GEODIST) !void {}

    pub const RedisCommand = struct {
        pub fn serialize(self: GEODIST, comptime rootSerializer: type, msg: var) !void {
            return rootSerializer.serializeCommand(msg, .{
                "GEODIST",
                self.key,
                self.member1,
                self.member2,
                self.unit,
            });
        }
    };
};

test "basic usage" {
    const cmd = GEODIST.init("cities", "rome", "paris", .meters);
}
