//! Link-only PE fixture. No build step executes or installs this image.
extern "kernel32" fn ExitProcess(code: u32) callconv(.winapi) noreturn;
// An observable mutable pointer forces a real DIR64 relocation in all modes.
export var fixture_code: u32 = 0;
export var fixture_pointer: *const u32 = &fixture_code;
pub export fn WinMainCRTStartup() callconv(.winapi) noreturn {
    ExitProcess(fixture_pointer.*);
}
