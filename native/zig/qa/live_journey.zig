//! Independent end-to-end T0.2c journey.
//!
//! This executable is a QA client, never a product dependency. It launches a
//! separately built TExFlow process, inspects its real UIA tree, invokes one
//! UIA TogglePattern mutation, and proves the resulting DWM-composed pixels through
//! DXGI Desktop Duplication plus a WIC PNG round-trip.

const std = @import("std");
const journey = @import("journey");
const capture = @import("capture_qa");
const argv = @import("windows_argv");
const windows = std.os.windows;

const Child = struct {
    process: windows.PROCESS.INFORMATION,

    fn wait(self: *const Child, milliseconds: u32) bool {
        return raw.WaitForSingleObject(self.process.hProcess, milliseconds) == raw.wait_object_0;
    }

    fn exitCode(self: *const Child) !u32 {
        if (!self.wait(15_000)) return error.ProductTimeout;
        var code: u32 = undefined;
        if (raw.GetExitCodeProcess(self.process.hProcess, &code) == 0) return error.ProductExitUnavailable;
        return code;
    }

    fn deinit(self: *Child) void {
        if (!self.wait(0)) {
            _ = raw.TerminateProcess(self.process.hProcess, 99);
            _ = raw.WaitForSingleObject(self.process.hProcess, 5_000);
        }
        windows.CloseHandle(self.process.hThread);
        windows.CloseHandle(self.process.hProcess);
    }
};

const raw = struct {
    const wait_object_0: u32 = 0;

    extern "kernel32" fn WaitForSingleObject(handle: windows.HANDLE, milliseconds: u32) callconv(.winapi) u32;
    extern "kernel32" fn GetExitCodeProcess(handle: windows.HANDLE, code: *u32) callconv(.winapi) i32;
    extern "kernel32" fn TerminateProcess(handle: windows.HANDLE, code: u32) callconv(.winapi) i32;
    extern "user32" fn MoveWindow(hwnd: ?*anyopaque, x: i32, y: i32, width: i32, height: i32, repaint: i32) callconv(.winapi) i32;
    extern "user32" fn GetSystemMetrics(index: i32) callconv(.winapi) i32;
    extern "user32" fn PostMessageW(hwnd: ?*anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) i32;
};

fn launch(allocator: std.mem.Allocator, io: std.Io, product_path: []const u8) !Child {
    const path = try std.Io.Dir.cwd().realPathFileAlloc(io, product_path, allocator);
    defer allocator.free(path);
    const directory = std.fs.path.dirname(path) orelse return error.InvalidProductPath;
    const arguments = [_][]const u8{"--trace-trial=00112233445566778899aabbccddeeff"};
    var prepared = try argv.prepare(allocator, .{
        .application_path = path,
        .arguments = &arguments,
        .current_directory = directory,
        .environment = &.{},
    });
    defer prepared.deinit(allocator);

    var startup: windows.STARTUPINFOW = std.mem.zeroes(windows.STARTUPINFOW);
    startup.cb = @sizeOf(windows.STARTUPINFOW);
    startup.dwFlags = 1; // STARTF_USESHOWWINDOW
    startup.wShowWindow = 5; // SW_SHOW
    var child: Child = undefined;
    if (!windows.kernel32.CreateProcessW(
        prepared.application_name.ptr,
        prepared.command_line.ptr,
        null,
        null,
        .FALSE,
        .{ .create_unicode_environment = true, .create_no_window = true },
        prepared.environment.ptr,
        prepared.current_directory.ptr,
        &startup,
        &child.process,
    ).toBool()) return error.ProductLaunchFailed;
    return child;
}

fn waitForWindow(child: *const Child) !journey.WindowInfo {
    var last_error: anyerror = error.InvalidWindow;
    for (0..250) |_| {
        if (journey.findWindowForProcess(child.process.dwProcessId)) |window| return window else |err| last_error = err;
        if (child.wait(20)) return error.ProductExitedBeforeWindow;
    }
    return last_error;
}

fn resizeForTriCanvas(window: journey.WindowInfo) !journey.WindowInfo {
    const screen_width = @max(raw.GetSystemMetrics(0), @as(i32, 1));
    const screen_height = @max(raw.GetSystemMetrics(1), @as(i32, 1));
    const width = @min(@as(i32, 1_900), @max(screen_width - 32, @as(i32, 1)));
    const height = @min(@as(i32, 1_100), @max(screen_height - 64, @as(i32, 1)));
    if (raw.MoveWindow(@ptrFromInt(window.hwnd), 0, 0, width, height, 1) == 0) return error.ResizeFailed;
    return journey.inspectWindow(.{ .hwnd = window.hwnd, .process_id = window.process_id });
}

const Receipt = struct {
    schema_version: u32,
    status: []const u8,
    product_pid: u32,
    hwnd: usize,
    bounds: Bounds,
    dpi: u16,
    marker_qpc: u64,
    frame_qpc: u64,
    generation: u64,
    output_index: u32,
    adapter_luid: u64,
    mode_width: u32,
    mode_height: u32,
    rotation: u16,
    full_output_sha256: []const u8,
    crop_sha256: []const u8,
    encoded_png_sha256: []const u8,
    ui_automation: journey.UiAutomationSummary,
    ui_automation_after: journey.UiAutomationSummary,
};

const Bounds = struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

fn writeEvidence(allocator: std.mem.Allocator, io: std.Io, output_path: []const u8, window: journey.WindowInfo, marker: journey.Marker, ui: journey.UiAutomationSummary, ui_after: journey.UiAutomationSummary, artifact: *capture.Artifact) !void {
    const output = try std.Io.Dir.openDirAbsolute(io, output_path, .{});
    defer output.close(io);
    try output.writeFile(io, .{ .sub_path = "shell.png", .data = artifact.png_bytes });

    var full_hex = std.fmt.bytesToHex(artifact.full_output_digest, .lower);
    var crop_hex = std.fmt.bytesToHex(artifact.crop_digest, .lower);
    var png_hex = std.fmt.bytesToHex(artifact.encoded_digest, .lower);
    const receipt = Receipt{
        .schema_version = 1,
        .status = "verified",
        .product_pid = window.process_id,
        .hwnd = window.hwnd,
        .bounds = .{
            .left = window.bounds.left,
            .top = window.bounds.top,
            .right = window.bounds.right,
            .bottom = window.bounds.bottom,
        },
        .dpi = window.dpi,
        .marker_qpc = marker.qpc,
        .frame_qpc = artifact.metadata.last_present_qpc,
        .generation = artifact.generation,
        .output_index = artifact.output.output_index,
        .adapter_luid = artifact.output.adapter_luid,
        .mode_width = artifact.output.mode_width,
        .mode_height = artifact.output.mode_height,
        .rotation = artifact.output.rotation,
        .full_output_sha256 = &full_hex,
        .crop_sha256 = &crop_hex,
        .encoded_png_sha256 = &png_hex,
        .ui_automation = ui,
        .ui_automation_after = ui_after,
    };
    const json = try std.json.Stringify.valueAlloc(allocator, receipt, .{});
    defer allocator.free(json);
    try output.writeFile(io, .{ .sub_path = "shell.receipt.json", .data = json });
}

fn run(allocator: std.mem.Allocator, io: std.Io, product_path: []const u8, output_path: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, output_path);
    var child = try launch(allocator, io, product_path);
    defer child.deinit();

    var window = try waitForWindow(&child);
    window = try resizeForTriCanvas(window);
    const ui = try journey.enumerateUiAutomation(window);
    if (!ui.open_folder or !ui.mode or !ui.compile or !ui.save or !ui.source or !ui.pdf or !ui.splitter or !ui.status or !ui.ready) {
        return error.IncompleteUiAutomationTree;
    }
    if (ui.invoke_patterns < 4 or ui.toggle_patterns < 1 or ui.range_value_patterns < 1 or ui.keyboard_focusable == 0) {
        return error.IncompleteUiAutomationPatterns;
    }

    // Exercise the standard control action bridge from this independent
    // process before the pixel marker. Compile is intentionally side-effect
    // free in T0.2c; its WM_COMMAND still requests a real frame.
    try journey.invokeUiAutomation(window, "Compile");

    var harness = try capture.Harness.arm(allocator, 0);
    defer harness.deinit();
    if (!ui.mode_off or ui.mode_on) return error.UiAutomationStateDidNotChange;
    const marker = try journey.mark(1);
    try journey.toggleUiAutomation(window, "Render mode");
    const ui_after = try journey.enumerateUiAutomation(window);
    if (!ui_after.mode_on or ui_after.mode_off) return error.UiAutomationStateDidNotChange;
    const frequency = try journey.qpcFrequency();
    const slack = std.math.mul(u64, frequency, 3) catch return error.DeadlineOverflow;
    const deadline = std.math.add(u64, marker.qpc, slack) catch return error.DeadlineOverflow;
    var artifact = try harness.captureAfter(.{
        .crop = window.bounds,
        .dpi = window.dpi,
        .marker_qpc = marker.qpc,
        .deadline_qpc = deadline,
        .expected_generation = harness.generation(),
    });
    defer artifact.deinit();
    try journey.requirePostMarker(marker, artifact.metadata.last_present_qpc);
    try writeEvidence(allocator, io, output_path, window, marker, ui, ui_after, &artifact);
    if (raw.PostMessageW(@ptrFromInt(window.hwnd), 0x0010, 0, 0) == 0) return error.CloseFailed;
    const exit_code = try child.exitCode();
    if (exit_code != 0) return error.ProductExitFailed;
    std.debug.print(
        "t0-2c-live-qa status=verified pid={d} dpi={d} frame_qpc={d} png_sha256={x}\n",
        .{ window.process_id, window.dpi, artifact.metadata.last_present_qpc, artifact.encoded_digest },
    );
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 6 or !std.mem.eql(u8, args[1], "run") or
        !std.mem.eql(u8, args[2], "--product") or !std.mem.eql(u8, args[4], "--output"))
    {
        return error.InvalidArguments;
    }
    try run(init.gpa, init.io, args[3], args[5]);
}
