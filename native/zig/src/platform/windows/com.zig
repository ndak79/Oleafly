//! Narrow UI-thread COM apartment binding. No activation or interfaces.
//! CoInitializeEx S_OK and S_FALSE each require one CoUninitialize; failed
//! HRESULT values (including RPC_E_CHANGED_MODE) never acquire an apartment.
//! https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-coinitializeex
pub const sta_flags: u32 = 0x2 | 0x4; // APARTMENTTHREADED | DISABLE_OLE1DDE
pub const mta_flags: u32 = 0x0 | 0x4; // MULTITHREADED | DISABLE_OLE1DDE

const raw = struct {
    extern "ole32" fn CoInitializeEx(?*anyopaque, u32) callconv(.winapi) i32;
    extern "ole32" fn CoUninitialize() callconv(.winapi) void;
};

pub fn succeeded(hresult: i32) bool {
    return hresult >= 0;
}

pub fn initializeSta() bool {
    return succeeded(raw.CoInitializeEx(null, sta_flags));
}

pub fn initializeMta() bool {
    return succeeded(raw.CoInitializeEx(null, mta_flags));
}

pub fn uninitialize() void {
    raw.CoUninitialize();
}
