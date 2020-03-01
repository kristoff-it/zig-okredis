pub const Key = struct {
    name: []const u8,

    pub fn init(key_name: []const u8) Key {
        return Key{key_name};
    }

    pub fn del(self: Key) DEL {
        return DEL.init(self.name);
    }
};
