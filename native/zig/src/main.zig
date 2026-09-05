const native = @import("shell_native");

// Zig supplies wWinMainCRTStartup; no hand-written CRT or console entry point.
// The UI role is fixed by the native adapter, never chosen by command line.
pub fn wWinMain(instance: native.HINSTANCE, previous: ?native.HINSTANCE, command_line: [*:0]u16, show: i32) callconv(.winapi) i32 {
    _ = previous;
    _ = command_line; // Explicit GetCommandLineW avoids a full-string/tail assumption.
    return @intFromEnum(native.launch(instance, show).code);
}
