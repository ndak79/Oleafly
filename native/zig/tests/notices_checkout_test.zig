const std = @import("std");
const notices = @import("notices");
const contract = @import("notices_contract");
const checkout = @import("notices_checkout_contract");
const testing = std.testing;
const allocator = testing.allocator;

// External QA-only Git fixture: explicit absolute executable, typed argv,
// no shell/PATH lookup, global configuration, hooks, or product dependency.
test "fresh Git checkout preserves exact notice bytes with core autocrlf true" {
    const io = testing.io;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    try temporary.dir.writeFile(io, .{ .sub_path = ".gitattributes", .data = contract.git_attributes });
    try temporary.dir.createDirPath(io, "native/zig");
    const notice_path = "native/zig/THIRD_PARTY_NOTICES.txt";
    try temporary.dir.writeFile(io, .{ .sub_path = notice_path, .data = contract.shipping_notice });
    allocator.free(try runCheckoutGit(root, &.{ "init", "--quiet", "." }));
    const attributes = try runCheckoutGit(root, &.{ "check-attr", "-z", "text", "eol", "--", notice_path });
    defer allocator.free(attributes);
    try testing.expectEqualStrings(notice_path ++ "\x00text\x00set\x00" ++ notice_path ++ "\x00eol\x00lf\x00", attributes);
    allocator.free(try runCheckoutGit(root, &.{ "add", "--", ".gitattributes", notice_path }));
    // Delete only this disposable fixture file, then materialize the exact
    // staged bytes through Git's checkout conversion. No commit is needed.
    try temporary.dir.deleteFile(io, notice_path);
    allocator.free(try runCheckoutGit(root, &.{ "checkout-index", "--force", "--", notice_path }));
    const checked_out = try temporary.dir.readFileAlloc(io, notice_path, allocator, .limited(64 * 1024));
    defer allocator.free(checked_out);
    try testing.expectEqualStrings(contract.shipping_notice, checked_out);
    var inventory = try notices.lockedInventory(allocator);
    defer inventory.deinit();
    try notices.validateShippingNotice(allocator, inventory.records, checked_out);
}

fn runCheckoutGit(root: []const u8, arguments: []const []const u8) ![]u8 {
    if (!std.fs.path.isAbsolute(checkout.git_executable)) return error.CheckoutGitMustBeAbsolute;
    const prefix = [_][]const u8{ checkout.git_executable, "-c", "core.autocrlf=true", "-c", "core.safecrlf=false", "-c", "core.hooksPath=", "-c", "core.attributesFile=", "-c", "core.fsmonitor=false", "-c", "init.templateDir=" };
    const argv = try std.mem.concat(allocator, []const u8, &.{ &prefix, arguments });
    defer allocator.free(argv);
    var environment = std.process.Environ.Map.init(allocator);
    defer environment.deinit();
    try environment.put("GIT_CONFIG_NOSYSTEM", "1");
    try environment.put("GIT_CONFIG_GLOBAL", if (@import("builtin").os.tag == .windows) "NUL" else "/dev/null");
    if (@import("builtin").os.tag == .windows) {
        const system_root = try testing.environ.getAlloc(allocator, "SystemRoot");
        defer allocator.free(system_root);
        try environment.put("SystemRoot", system_root);
    }
    const result = try std.process.run(allocator, testing.io, .{
        .argv = argv,
        .cwd = .{ .path = root },
        .environ_map = &environment,
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
        .timeout = .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(10) } },
        .create_no_window = true,
    });
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) {
            std.debug.print("Git checkout fixture failed ({d}): {s}\n", .{ code, result.stderr });
            return error.CheckoutGitFailed;
        },
        else => return error.CheckoutGitFailed,
    }
    return result.stdout;
}
