//  GEOADD key longitude latitude member [longitude latitude member ...]

const std = @import("std");

pub const GEOADD = struct {
    key: []const u8,
    points: []const GeoPoint,

    pub const GeoPoint = struct {
        long: f64,
        lat: f64,
        member: []const u8,

        pub const RedisArguments = struct {
            pub fn count(_: GeoPoint) usize {
                return 3;
            }

            pub fn serialize(self: GeoPoint, comptime rootSerializer: type, msg: anytype) !void {
                try rootSerializer.serializeArgument(msg, f64, self.long);
                try rootSerializer.serializeArgument(msg, f64, self.lat);
                try rootSerializer.serializeArgument(msg, []const u8, self.member);
            }
        };
    };

    /// Instantiates a new GEOADD command.
    pub fn init(key: []const u8, points: []const GeoPoint) GEOADD {
        return .{ .key = key, .points = points };
    }

    /// Validates if the command is syntactically correct.
    pub fn validate(self: GEOADD) !void {
        if (self.points.len == 0) return error.PointsArrayIsEmpty;
    }

    pub const RedisCommand = struct {
        pub fn serialize(self: GEOADD, comptime rootSerializer: type, msg: anytype) !void {
            return rootSerializer.serializeCommand(msg, .{ "GEOADD", self.key, self.points });
        }
    };
};

test "basic usage" {
    const cmd = GEOADD.init("mykey", &[_]GEOADD.GeoPoint{
        .{ .long = 80.05, .lat = 80.05, .member = "place1" },
        .{ .long = 81.05, .lat = 81.05, .member = "place2" },
    });

    try cmd.validate();
}
