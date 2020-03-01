const Key = @import("./key.zig");
const cmds = @import("../commands.zig");

const String = struct {
    key: Key,

    pub fn init(key_name: []u8) String {
        return String{Key{key_name}};
    }

    pub fn set(self: String, newVal: []u8) cmds.SET {
        return SET.init(self.key.name, newVal);
    }

    pub fn get(self: String) cmds.GET {
        return GET.init(self.key.name);
    }
};
