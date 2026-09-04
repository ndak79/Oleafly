pub const AbiVersion = extern struct {
    major: u32,
    minor: u32,
    patch: u32,
};

pub const abi_ok: i32 = 0;
pub const abi_invalid_argument: i32 = -1;

pub export fn oleafly_abi_get_version(out: ?*AbiVersion) callconv(.c) i32 {
    const destination = out orelse return abi_invalid_argument;
    destination.* = .{
        .major = 0,
        .minor = 1,
        .patch = 0,
    };
    return abi_ok;
}

pub export fn oleafly_abi_add(a: i64, b: i64) callconv(.c) i64 {
    return a +% b;
}
