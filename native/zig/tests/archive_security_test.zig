const std = @import("std");
const deps = @import("deps");
const unicode = @import("unicode");

const release_query =
    "sp=r&sv=2018-11-09&sr=b&spr=https&se=2030-01-01T00%3A00%3A00Z" ++
    "&rscd=attachment%3B+filename%3Dfixture.tgz&rsct=application%2Foctet-stream" ++
    "&skoid=11111111-1111-4111-8111-111111111111" ++
    "&sktid=22222222-2222-4222-8222-222222222222" ++
    "&skt=2029-01-01T00%3A00%3A00Z&ske=2030-01-01T00%3A00%3A00Z" ++
    "&sks=b&skv=2018-11-09&sig=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA%3D" ++
    "&jwt=locked.jwt.value" ++
    "&response-content-disposition=attachment%3B%20filename%3Dfixture.tgz" ++
    "&response-content-type=application%2Foctet-stream";

test "download redirect policy accepts only reviewed exact origins and asset repositories" {
    try deps.validateDownloadTarget(
        "scintilla",
        "https://www.scintilla.org/scintilla566.tgz?download=1",
    );
    try deps.validateDownloadTarget(
        "zigwin32",
        "https://codeload.github.com/marlersoft/zigwin32/tar.gz/9f15c276b4e9d05afd34a10d8662a7dfc34647ea",
    );
    try deps.validateDownloadTarget(
        "pdfium-build-recipe",
        "https://codeload.github.com/bblanchon/pdfium-binaries/tar.gz/5453f3afc4785cbad82c05f6ceb4dabea0cb81a0",
    );

    const release_url = try std.fmt.allocPrint(
        std.testing.allocator,
        "https://release-assets.githubusercontent.com/github-production-release-asset/103962638/e001e65b-2a8c-424c-9dd2-82e0a18b40ca?{s}",
        .{release_query},
    );
    defer std.testing.allocator.free(release_url);
    try deps.validateDownloadTarget("pdfium-reference", release_url);
}

test "download redirect policy rejects authority path and signed-query drift" {
    const hostile = [_]struct { id: []const u8, url: []const u8 }{
        .{ .id = "scintilla", .url = "http://www.scintilla.org/scintilla566.tgz" },
        .{ .id = "scintilla", .url = "https://user@www.scintilla.org/scintilla566.tgz" },
        .{ .id = "scintilla", .url = "https://www.scintilla.org:443/scintilla566.tgz" },
        .{ .id = "scintilla", .url = "https://www.scintilla.org/scintilla566.tgz" },
        .{ .id = "scintilla", .url = "https://www.scintilla.org/scintilla566.tgz#fragment" },
        .{ .id = "scintilla", .url = "https://evil.example/scintilla566.tgz" },
        .{ .id = "zigwin32", .url = "https://codeload.github.com/marlersoft/zigwin32/tar.gz/wrong" },
        .{ .id = "pdfium-reference", .url = "https://release-assets.githubusercontent.com/github-production-release-asset/999/e001e65b-2a8c-424c-9dd2-82e0a18b40ca?x=y" },
        .{ .id = "pdfium-reference", .url = "https://release-assets.githubusercontent.com/github-production-release-asset/103962638/not-a-uuid?x=y" },
        .{ .id = "pdfium-reference", .url = "https://release-assets.githubusercontent.com/github-production-release-asset/103962638/e001e65b-2a8c-424c-9dd2-82e0a18b40ca?sp=r" },
    };
    for (hostile) |case| {
        try std.testing.expectError(
            error.UnapprovedDownloadTarget,
            deps.validateDownloadTarget(case.id, case.url),
        );
    }

    const duplicate_query = try std.fmt.allocPrint(
        std.testing.allocator,
        "https://release-assets.githubusercontent.com/github-production-release-asset/103962638/e001e65b-2a8c-424c-9dd2-82e0a18b40ca?{s}&sp=r",
        .{release_query},
    );
    defer std.testing.allocator.free(duplicate_query);
    try std.testing.expectError(
        error.UnapprovedDownloadTarget,
        deps.validateDownloadTarget("pdfium-reference", duplicate_query),
    );
}

test "download redirect tracker rejects loops and more than three hops" {
    var loop = deps.RedirectTracker.init("https://example.test/a");
    try loop.follow("https://example.test/b");
    try std.testing.expectError(
        error.DownloadRedirectLoop,
        loop.follow("https://example.test/a"),
    );

    var too_many = deps.RedirectTracker.init("https://example.test/0");
    try too_many.follow("https://example.test/1");
    try too_many.follow("https://example.test/2");
    try too_many.follow("https://example.test/3");
    try std.testing.expectError(
        error.TooManyDownloadRedirects,
        too_many.follow("https://example.test/4"),
    );
}

fn releaseUrlWithQueryReplacement(needle: []const u8, replacement: []const u8) ![]u8 {
    const query = try std.mem.replaceOwned(u8, std.testing.allocator, release_query, needle, replacement);
    defer std.testing.allocator.free(query);
    return std.fmt.allocPrint(
        std.testing.allocator,
        "https://release-assets.githubusercontent.com/github-production-release-asset/103962638/e001e65b-2a8c-424c-9dd2-82e0a18b40ca?{s}",
        .{query},
    );
}

test "download redirect policy accepts matching dispositions up to 512 decoded bytes" {
    const encoded_filename = "%61" ** 491;
    for ([_]usize{ 511, 512 }) |decoded_len| {
        const replacement = try std.fmt.allocPrint(
            std.testing.allocator,
            "filename%3D{s}",
            .{encoded_filename[0 .. 3 * (decoded_len - "attachment; filename=".len)]},
        );
        defer std.testing.allocator.free(replacement);
        const url = try releaseUrlWithQueryReplacement("filename%3Dfixture.tgz", replacement);
        defer std.testing.allocator.free(url);
        try deps.validateDownloadTarget("pdfium-reference", url);
    }
}

test "download redirect policy rejects rscd over 512 decoded bytes" {
    const url = try releaseUrlWithQueryReplacement(
        "rscd=attachment%3B+filename%3Dfixture.tgz",
        "rscd=attachment%3B+filename%3D" ++ "%61" ** 492,
    );
    defer std.testing.allocator.free(url);
    try std.testing.expectError(error.UnapprovedDownloadTarget, deps.validateDownloadTarget("pdfium-reference", url));
}

test "download redirect policy rejects response disposition over 512 decoded bytes" {
    const url = try releaseUrlWithQueryReplacement(
        "response-content-disposition=attachment%3B%20filename%3Dfixture.tgz",
        "response-content-disposition=attachment%3B%20filename%3D" ++ "%61" ** 492,
    );
    defer std.testing.allocator.free(url);
    try std.testing.expectError(error.UnapprovedDownloadTarget, deps.validateDownloadTarget("pdfium-reference", url));
}

test "download redirect policy rejects JWT dot counts without counter overflow" {
    const dots = "." ** 258;
    for ([_]usize{ 3, 255, 256, 258 }) |dot_count| {
        const jwt = try std.fmt.allocPrint(std.testing.allocator, "a{s}z", .{dots[0..dot_count]});
        defer std.testing.allocator.free(jwt);
        const url = try releaseUrlWithQueryReplacement("locked.jwt.value", jwt);
        defer std.testing.allocator.free(url);
        try std.testing.expectError(error.UnapprovedDownloadTarget, deps.validateDownloadTarget("pdfium-reference", url));
    }
}

test "download verifier blocks truncation limits digest drift and interrupted activation" {
    const abc_digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    var artifact = deps.Artifact{
        .id = "fixture",
        .version = "1",
        .purpose = "transport fixture",
        .source_url = "https://example.test/source",
        .license_spdx = "MIT",
        .license_url = "https://example.test/license",
        .url = "https://example.test/archive",
        .allowed_path_prefix = "/archive",
        .integrity = .byte_archive,
        .archive_format = .direct_file,
        .archive_root = "",
        .archive_size_bytes = 3,
        .archive_sha256 = abc_digest,
        .expected_entries = 1,
        .download_limit_bytes = 3,
        .expanded_limit_bytes = 3,
        .dependencies = &.{},
        .build_switches = &.{},
    };

    var valid = try deps.DownloadVerifier.init(artifact, 3);
    try valid.feed("a");
    try valid.feed("bc");
    try valid.finish();
    try std.testing.expect(valid.mayActivate());

    try std.testing.expectError(
        error.ContentLengthMismatch,
        deps.DownloadVerifier.init(artifact, 2),
    );

    var truncated = try deps.DownloadVerifier.init(artifact, null);
    try truncated.feed("ab");
    try std.testing.expectError(error.DownloadSizeMismatch, truncated.finish());
    try std.testing.expect(!truncated.mayActivate());

    artifact.archive_sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    var corrupt = try deps.DownloadVerifier.init(artifact, 3);
    try corrupt.feed("abc");
    try std.testing.expectError(error.DigestMismatch, corrupt.finish());
    try std.testing.expect(!corrupt.mayActivate());

    artifact.archive_sha256 = abc_digest;
    var oversized = try deps.DownloadVerifier.init(artifact, null);
    try std.testing.expectError(error.DownloadLimitExceeded, oversized.feed("abcd"));
    try std.testing.expect(!oversized.mayActivate());

    var interrupted = try deps.DownloadVerifier.init(artifact, null);
    try interrupted.feed("a");
    interrupted.markTransportFailure();
    try std.testing.expectError(error.DownloadIncomplete, interrupted.finish());
    try std.testing.expect(!interrupted.mayActivate());
}

test "Windows archive paths reject escape and ambiguous namespaces" {
    try deps.validateArchivePath("scintilla/src/Editor.cxx");

    const hostile = [_][]const u8{
        "/absolute",
        "\\absolute",
        "C:\\drive",
        "C:/drive",
        "\\\\server\\share",
        "\\\\?\\C:\\device",
        "\\\\.\\PIPE\\device",
        "safe/file.txt:stream",
        "../escape",
        "safe/../escape",
        "safe/./file",
        "safe//file",
        "CON",
        "con.txt",
        "CONIN$",
        "conout$.txt",
        "LPT9.log",
        "COM\u{b9}.txt",
        "com\u{b2}",
        "LPT\u{b3}.log",
        "safe/name.",
        "safe/name ",
        "safe/quo\"te.tex",
        "safe/star*.tex",
        "safe/query?.tex",
        "safe/less<.tex",
        "safe/more>.tex",
        "safe/pipe|.tex",
        "LONGFI~1.TXT",
        "safe/\x00name",
        "safe/\x1fname",
        "safe/\x7fname",
    };
    for (hostile) |path| {
        try std.testing.expectError(error.UnsafeArchivePath, deps.validateArchivePath(path));
    }
}

test "path registry rejects exact, Windows-case, and Unicode-normalized collisions" {
    var registry = deps.PathRegistry.initWithFold(std.testing.allocator, unicode.foldNfd);
    defer registry.deinit();

    try registry.add("root/Paper.txt");
    try std.testing.expectError(error.PathCollision, registry.add("root/Paper.txt"));
    try std.testing.expectError(error.PathCollision, registry.add("ROOT/paper.TXT"));

    try registry.add("root/caf\u{00e9}.tex");
    try std.testing.expectError(error.PathCollision, registry.add("root/cafe\u{0301}.tex"));

    try registry.add("root/Straße.tex");
    try std.testing.expectError(error.PathCollision, registry.add("root/strasse.tex"));

    try registry.add("root/\u{212a}elvin.tex");
    try std.testing.expectError(error.PathCollision, registry.add("root/kelvin.tex"));
}

const TarEntry = struct {
    name: []const u8,
    kind: u8 = '0',
    data: []const u8 = "",
    declared_size: ?u64 = null,
    mtime: u64 = 0,
};

const hostile_archive_member_paths = [_][]const u8{
    "/absolute",
    "\\absolute",
    "C:\\drive",
    "C:/drive",
    "\\\\server\\share",
    "\\\\?\\C:\\device",
    "\\\\.\\PIPE\\device",
    "root/file.txt:stream",
    "../escape",
    "root/../escape",
    "root/./file",
    "root//file",
    "root/CON",
    "root/con.txt",
    "root/CONIN$",
    "root/conout$.txt",
    "root/LPT9.log",
    "root/COM\u{b9}.txt",
    "root/com\u{b2}",
    "root/LPT\u{b3}.log",
    "root/name.",
    "root/name ",
    "root/quo\"te.tex",
    "root/star*.tex",
    "root/query?.tex",
    "root/less<.tex",
    "root/more>.tex",
    "root/pipe|.tex",
    "root/LONGFI~1.TXT",
    "root/a\x00../evil",
    "root/\x1fname",
    "root/\x7fname",
};

fn makeTar(allocator: std.mem.Allocator, entries: []const TarEntry) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    for (entries) |entry| {
        var header = [_]u8{0} ** 512;
        if (entry.name.len > 100) return error.NameTooLong;
        @memcpy(header[0..entry.name.len], entry.name);
        writeOctal(header[100..108], 0o644);
        writeOctal(header[108..116], 0);
        writeOctal(header[116..124], 0);
        writeOctal(header[124..136], entry.declared_size orelse entry.data.len);
        writeOctal(header[136..148], entry.mtime);
        @memset(header[148..156], ' ');
        header[156] = entry.kind;
        @memcpy(header[257..263], "ustar\x00");
        @memcpy(header[263..265], "00");
        var checksum: u64 = 0;
        for (header) |byte| checksum += byte;
        writeChecksum(header[148..156], checksum);
        try output.writer.writeAll(&header);
        try output.writer.writeAll(entry.data);
        const padding = (512 - (entry.data.len % 512)) % 512;
        try output.writer.splatByteAll(0, padding);
    }
    try output.writer.splatByteAll(0, 1024);
    return output.toOwnedSlice();
}

fn writeOctal(field: []u8, value: u64) void {
    @memset(field, '0');
    field[field.len - 1] = 0;
    var remaining = value;
    var index = field.len - 2;
    while (remaining != 0) {
        field[index] = @intCast('0' + remaining % 8);
        remaining /= 8;
        if (index == 0) break;
        index -= 1;
    }
}

fn writeChecksum(field: []u8, value: u64) void {
    writeOctal(field[0..7], value);
    field[6] = 0;
    field[7] = ' ';
}

fn rewriteTarChecksum(header: []u8) void {
    @memset(header[148..156], ' ');
    var checksum: u64 = 0;
    for (header[0..512]) |byte| checksum += byte;
    writeChecksum(header[148..156], checksum);
}

fn gzip(
    allocator: std.mem.Allocator,
    plain: []const u8,
    options: std.compress.flate.Compress.Options,
) ![]u8 {
    const capacity = plain.len + 4096;
    const buffer = try allocator.alloc(u8, capacity);
    defer allocator.free(buffer);
    var output = std.Io.Writer.fixed(buffer);
    var history: [std.compress.flate.max_window_len * 2]u8 = undefined;
    var compressor = try std.compress.flate.Compress.init(
        &output,
        &history,
        .gzip,
        options,
    );
    try compressor.writer.writeAll(plain);
    try compressor.finish();
    return allocator.dupe(u8, output.buffered());
}

fn limits() deps.ArchiveLimits {
    return .{
        .max_compressed_bytes = 256 * 1024,
        .max_decompressed_bytes = 256 * 1024,
        .max_member_bytes = 128 * 1024,
        .max_total_bytes = 192 * 1024,
        .max_entries = 8,
        .max_compression_ratio = 100,
        .required_root = "root/",
        .collision_fold = unicode.foldNfd,
    };
}

test "tar gzip inspection accepts one bounded regular file" {
    const tar = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/file.txt", .data = "abc" },
    });
    defer std.testing.allocator.free(tar);
    const compressed = try gzip(std.testing.allocator, tar, .default);
    defer std.testing.allocator.free(compressed);

    const summary = try deps.inspectTarGzip(std.testing.allocator, compressed, limits());
    try std.testing.expectEqual(@as(u32, 1), summary.entries);
    try std.testing.expectEqual(@as(u64, 3), summary.content_bytes);
}

test "tar allowlist accepts exact metadata and approved trees only" {
    var allowlisted = limits();
    allowlisted.max_entries = 4;
    allowlisted.allowed_exact_paths = &.{"root/LICENSE"};
    allowlisted.allowed_path_prefixes = &.{"root/bin/"};

    const valid = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/LICENSE", .data = "license" },
        .{ .name = "root/bin/", .kind = '5' },
        .{ .name = "root/bin/tool.exe", .data = "binary" },
    });
    defer std.testing.allocator.free(valid);
    const summary = try deps.inspectTar(std.testing.allocator, valid, allowlisted);
    try std.testing.expectEqual(@as(u32, 3), summary.entries);

    const unexpected = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/LICENSE", .data = "license" },
        .{ .name = "root/tools/hidden.exe", .data = "binary" },
    });
    defer std.testing.allocator.free(unexpected);
    try std.testing.expectError(
        error.UnapprovedArchiveMember,
        deps.inspectTar(std.testing.allocator, unexpected, allowlisted),
    );
}

test "verified materialization writes through handles and rehashes exact payload" {
    const tar = try makeTar(std.testing.allocator, &.{.{
        .name = "root/paper.tex",
        .data = "abc",
    }});
    defer std.testing.allocator.free(tar);
    const compressed = try gzip(std.testing.allocator, tar, .default);
    defer std.testing.allocator.free(compressed);
    const artifact = deps.Artifact{
        .id = "fixture",
        .version = "1",
        .purpose = "materialization fixture",
        .source_url = "https://example.test/source",
        .license_spdx = "MIT",
        .license_url = "https://example.test/license",
        .url = "https://example.test/archive",
        .allowed_path_prefix = "/archive",
        .integrity = .byte_archive,
        .archive_format = .tar_gzip,
        .archive_root = "root/",
        .archive_size_bytes = compressed.len,
        .archive_sha256 = "0000000000000000000000000000000000000000000000000000000000000000",
        .expected_entries = 1,
        .download_limit_bytes = 256 * 1024,
        .expanded_limit_bytes = 256 * 1024,
        .dependencies = &.{},
        .build_switches = &.{},
    };

    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();
    const expected = try deps.materializeArtifact(
        std.testing.allocator,
        std.testing.io,
        artifact,
        compressed,
        temp.dir,
        unicode.foldNfd,
    );
    const actual = try deps.hashMaterializedDirectory(
        std.testing.allocator,
        std.testing.io,
        temp.dir,
        artifact.expanded_limit_bytes,
    );
    try std.testing.expectEqual(expected.payload_files, actual.files);
    try std.testing.expectEqual(expected.payload_bytes, actual.bytes);
    try std.testing.expectEqualSlices(u8, &expected.payload_sha256, &actual.digest);

    try temp.dir.createDir(std.testing.io, "unexpected-empty", .default_dir);
    try std.testing.expectError(
        error.UnexpectedEmptyDirectory,
        deps.hashMaterializedDirectory(
            std.testing.allocator,
            std.testing.io,
            temp.dir,
            artifact.expanded_limit_bytes,
        ),
    );

    var file = try temp.dir.openFile(
        std.testing.io,
        "root/paper.tex",
        .{ .follow_symlinks = true },
    );
    defer file.close(std.testing.io);
    var reader_buffer: [16]u8 = undefined;
    var reader = file.reader(std.testing.io, &reader_buffer);
    const bytes = try reader.interface.allocRemaining(std.testing.allocator, .limited(4));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("abc", bytes);
}

test "Gitiles canonical tree ignores transport metadata and locks content records" {
    const tar_a = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/b.txt", .data = "beta", .mtime = 1 },
        .{ .name = "root/a.txt", .data = "alpha", .mtime = 2 },
    });
    defer std.testing.allocator.free(tar_a);
    const tar_b = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "alpha", .mtime = 99 },
        .{ .name = "root/b.txt", .data = "beta", .mtime = 100 },
    });
    defer std.testing.allocator.free(tar_b);
    const gzip_a = try gzip(std.testing.allocator, tar_a, .fastest);
    defer std.testing.allocator.free(gzip_a);
    const gzip_b = try gzip(std.testing.allocator, tar_b, .best);
    defer std.testing.allocator.free(gzip_b);
    try std.testing.expect(!std.mem.eql(u8, gzip_a, gzip_b));

    const digest_a = try deps.canonicalTreeDigestTarGzip(
        std.testing.allocator,
        gzip_a,
        limits(),
        2,
    );
    const digest_b = try deps.canonicalTreeDigestTarGzip(
        std.testing.allocator,
        gzip_b,
        limits(),
        2,
    );
    try std.testing.expectEqualSlices(u8, &digest_a, &digest_b);

    const changed = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "Alpha", .mtime = 99 },
        .{ .name = "root/b.txt", .data = "beta", .mtime = 100 },
    });
    defer std.testing.allocator.free(changed);
    const changed_digest = try deps.canonicalTreeDigest(
        std.testing.allocator,
        changed,
        limits(),
        2,
    );
    try std.testing.expect(!std.mem.eql(u8, &digest_a, &changed_digest));
    try std.testing.expectError(
        error.CanonicalTreeFileCountMismatch,
        deps.canonicalTreeDigest(std.testing.allocator, tar_a, limits(), 3),
    );
}

test "tar rejects hostile paths, links, special entries, and metadata overrides" {
    for (hostile_archive_member_paths) |path| {
        const tar = try makeTar(std.testing.allocator, &.{
            .{ .name = path, .data = "x" },
        });
        defer std.testing.allocator.free(tar);
        try std.testing.expectError(
            error.UnsafeArchivePath,
            deps.inspectTar(std.testing.allocator, tar, limits()),
        );
        const compressed = try gzip(std.testing.allocator, tar, .default);
        defer std.testing.allocator.free(compressed);
        try std.testing.expectError(
            error.UnsafeArchivePath,
            deps.inspectTarGzip(std.testing.allocator, compressed, limits()),
        );
    }

    const unicode_collision = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/caf\u{00e9}.tex", .data = "a" },
        .{ .name = "root/cafe\u{0301}.tex", .data = "b" },
    });
    defer std.testing.allocator.free(unicode_collision);
    try std.testing.expectError(
        error.PathCollision,
        deps.inspectTar(std.testing.allocator, unicode_collision, limits()),
    );
    const compressed_collision = try gzip(std.testing.allocator, unicode_collision, .default);
    defer std.testing.allocator.free(compressed_collision);
    try std.testing.expectError(
        error.PathCollision,
        deps.inspectTarGzip(std.testing.allocator, compressed_collision, limits()),
    );

    const rejected_types = [_]u8{ '1', '2', '3', '4', '6', 'S', 'x', 'g', 'K' };
    for (rejected_types) |kind| {
        const tar = try makeTar(std.testing.allocator, &.{
            .{ .name = "root/entry", .kind = kind },
        });
        defer std.testing.allocator.free(tar);
        try std.testing.expectError(
            error.UnsupportedTarEntry,
            deps.inspectTar(std.testing.allocator, tar, limits()),
        );
    }

    const bare_long_name = try makeTar(std.testing.allocator, &.{.{
        .name = "././@LongLink",
        .kind = 'L',
    }});
    defer std.testing.allocator.free(bare_long_name);
    try std.testing.expectError(
        error.UnsafeGnuLongName,
        deps.inspectTar(std.testing.allocator, bare_long_name, limits()),
    );
}

test "tar name and prefix reject hidden bytes after their first NUL" {
    const hidden_name = try makeTar(std.testing.allocator, &.{.{
        .name = "root/a\x00../hidden",
        .data = "x",
    }});
    defer std.testing.allocator.free(hidden_name);
    try std.testing.expectError(
        error.UnsafeArchivePath,
        deps.inspectTar(std.testing.allocator, hidden_name, limits()),
    );
    try std.testing.expectError(
        error.UnsafeArchivePath,
        deps.canonicalTreeDigest(std.testing.allocator, hidden_name, limits(), 1),
    );

    const hidden_prefix = try makeTar(std.testing.allocator, &.{.{
        .name = "a.txt",
        .data = "x",
    }});
    defer std.testing.allocator.free(hidden_prefix);
    @memcpy(hidden_prefix[345..][0..11], "root\x00hidden");
    rewriteTarChecksum(hidden_prefix[0..512]);
    try std.testing.expectError(
        error.UnsafeArchivePath,
        deps.inspectTar(std.testing.allocator, hidden_prefix, limits()),
    );
    try std.testing.expectError(
        error.UnsafeArchivePath,
        deps.canonicalTreeDigest(std.testing.allocator, hidden_prefix, limits(), 1),
    );
}

test "tar accepts only a strict GNU long-name record bound to the next header prefix" {
    var gnu_limits = limits();
    gnu_limits.tar_metadata_policy = .gnu_long_name;
    var long_name_storage: [112]u8 = undefined;
    @memcpy(long_name_storage[0..5], "root/");
    @memset(long_name_storage[5..108], 'a');
    @memcpy(long_name_storage[108..], ".tex");
    var long_body: [113]u8 = undefined;
    @memcpy(long_body[0..112], &long_name_storage);
    long_body[112] = 0;

    const valid = try makeTar(std.testing.allocator, &.{
        .{ .name = "././@LongLink", .kind = 'L', .data = &long_body },
        .{ .name = long_name_storage[0..100], .data = "x" },
    });
    defer std.testing.allocator.free(valid);
    const summary = try deps.inspectTar(std.testing.allocator, valid, gnu_limits);
    try std.testing.expectEqual(@as(u32, 1), summary.entries);

    const ambiguous = try makeTar(std.testing.allocator, &.{
        .{ .name = "././@LongLink", .kind = 'L', .data = &long_body },
        .{ .name = "root/not-the-long-name", .data = "x" },
    });
    defer std.testing.allocator.free(ambiguous);
    try std.testing.expectError(
        error.UnsafeGnuLongName,
        deps.inspectTar(std.testing.allocator, ambiguous, gnu_limits),
    );
}

test "Gitiles PAX accepts only bound mtime and path metadata" {
    var pax_limits = limits();
    pax_limits.tar_metadata_policy = .gitiles_pax;
    const mtime = "28 mtime=1788528488.8850000\n";

    const valid = try makeTar(std.testing.allocator, &.{
        .{ .name = "./PaxHeaders.X/root_file.txt", .kind = 'x', .data = mtime },
        .{ .name = "root/file.txt", .data = "x" },
    });
    defer std.testing.allocator.free(valid);
    const summary = try deps.inspectTar(std.testing.allocator, valid, pax_limits);
    try std.testing.expectEqual(@as(u32, 1), summary.entries);

    var hundred_byte_path = [_]u8{'a'} ** 100;
    @memcpy(hundred_byte_path[0..5], "root/");
    var truncated_pax_name: [99]u8 = undefined;
    const pax_prefix = "./PaxHeaders.X/";
    @memcpy(truncated_pax_name[0..pax_prefix.len], pax_prefix);
    for (
        hundred_byte_path[0 .. truncated_pax_name.len - pax_prefix.len],
        pax_prefix.len..,
    ) |byte, index| {
        truncated_pax_name[index] = if (byte == '/') '_' else byte;
    }
    const path_body = try std.fmt.allocPrint(
        std.testing.allocator,
        "110 path={s}\n{s}",
        .{ &hundred_byte_path, mtime },
    );
    defer std.testing.allocator.free(path_body);
    const valid_path_override = try makeTar(std.testing.allocator, &.{
        .{ .name = &truncated_pax_name, .kind = 'x', .data = path_body },
        .{ .name = &hundred_byte_path, .data = "x" },
    });
    defer std.testing.allocator.free(valid_path_override);
    const override_summary = try deps.inspectTar(
        std.testing.allocator,
        valid_path_override,
        pax_limits,
    );
    try std.testing.expectEqual(@as(u32, 1), override_summary.entries);

    const unknown_key = try makeTar(std.testing.allocator, &.{
        .{ .name = "./PaxHeaders.X/root_file.txt", .kind = 'x', .data = mtime ++ "12 uid=1000\n" },
        .{ .name = "root/file.txt", .data = "x" },
    });
    defer std.testing.allocator.free(unknown_key);
    try std.testing.expectError(
        error.UnsafePaxMetadata,
        deps.inspectTar(std.testing.allocator, unknown_key, pax_limits),
    );

    const mismatched_path = try makeTar(std.testing.allocator, &.{
        .{ .name = "./PaxHeaders.X/root_evil.txt", .kind = 'x', .data = "22 path=root/evil.txt\n" ++ mtime },
        .{ .name = "root/file.txt", .data = "x" },
    });
    defer std.testing.allocator.free(mismatched_path);
    try std.testing.expectError(
        error.UnsafePaxMetadata,
        deps.inspectTar(std.testing.allocator, mismatched_path, pax_limits),
    );

    const malformed_length = try makeTar(std.testing.allocator, &.{
        .{ .name = "./PaxHeaders.X/root_file.txt", .kind = 'x', .data = "27 mtime=1788528488.8850000\n" },
        .{ .name = "root/file.txt", .data = "x" },
    });
    defer std.testing.allocator.free(malformed_length);
    try std.testing.expectError(
        error.UnsafePaxMetadata,
        deps.inspectTar(std.testing.allocator, malformed_length, pax_limits),
    );
}

test "GitHub Codeload accepts one commit-bound global PAX comment" {
    const commit = "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0";
    var codeload_limits = limits();
    codeload_limits.tar_metadata_policy = .github_codeload_pax;
    codeload_limits.tar_metadata_identity = commit;
    const valid = try makeTar(std.testing.allocator, &.{
        .{ .name = "pax_global_header", .kind = 'g', .data = "52 comment=" ++ commit ++ "\n" },
        .{ .name = "root/file.txt", .data = "x" },
    });
    defer std.testing.allocator.free(valid);
    const summary = try deps.inspectTar(std.testing.allocator, valid, codeload_limits);
    try std.testing.expectEqual(@as(u32, 1), summary.entries);

    const wrong_commit = try makeTar(std.testing.allocator, &.{
        .{ .name = "pax_global_header", .kind = 'g', .data = "52 comment=0000000000000000000000000000000000000000\n" },
        .{ .name = "root/file.txt", .data = "x" },
    });
    defer std.testing.allocator.free(wrong_commit);
    try std.testing.expectError(
        error.UnsafePaxMetadata,
        deps.inspectTar(std.testing.allocator, wrong_commit, codeload_limits),
    );

    const late_header = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/file.txt", .data = "x" },
        .{ .name = "pax_global_header", .kind = 'g', .data = "52 comment=" ++ commit ++ "\n" },
    });
    defer std.testing.allocator.free(late_header);
    try std.testing.expectError(
        error.UnsafePaxMetadata,
        deps.inspectTar(std.testing.allocator, late_header, codeload_limits),
    );
}

test "tar rejects duplicate Windows names and malformed numeric or checksum fields" {
    const duplicate = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/Paper.txt", .data = "a" },
        .{ .name = "root/paper.TXT", .data = "b" },
    });
    defer std.testing.allocator.free(duplicate);
    try std.testing.expectError(
        error.PathCollision,
        deps.inspectTar(std.testing.allocator, duplicate, limits()),
    );

    const bad_checksum = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/file.txt", .data = "a" },
    });
    defer std.testing.allocator.free(bad_checksum);
    bad_checksum[0] = 'R';
    try std.testing.expectError(
        error.InvalidTarChecksum,
        deps.inspectTar(std.testing.allocator, bad_checksum, limits()),
    );

    const base_256 = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/file.txt", .data = "a" },
    });
    defer std.testing.allocator.free(base_256);
    base_256[124] |= 0x80;
    @memset(base_256[148..156], ' ');
    var checksum: u64 = 0;
    for (base_256[0..512]) |byte| checksum += byte;
    writeChecksum(base_256[148..156], checksum);
    try std.testing.expectError(
        error.InvalidTarNumber,
        deps.inspectTar(std.testing.allocator, base_256, limits()),
    );
}

test "tar enforces entry, member, total, stream, and compression bounds" {
    const two = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/a", .data = "aaa" },
        .{ .name = "root/b", .data = "bbb" },
    });
    defer std.testing.allocator.free(two);

    var bounded = limits();
    bounded.max_entries = 1;
    try std.testing.expectError(
        error.TooManyArchiveEntries,
        deps.inspectTar(std.testing.allocator, two, bounded),
    );
    bounded = limits();
    bounded.max_member_bytes = 2;
    try std.testing.expectError(
        error.ArchiveMemberTooLarge,
        deps.inspectTar(std.testing.allocator, two, bounded),
    );
    bounded = limits();
    bounded.max_member_bytes = 5;
    bounded.max_total_bytes = 5;
    try std.testing.expectError(
        error.ArchiveExpandedTooLarge,
        deps.inspectTar(std.testing.allocator, two, bounded),
    );

    try std.testing.expectError(
        error.TruncatedTar,
        deps.inspectTar(std.testing.allocator, two[0 .. two.len - 1], limits()),
    );

    const compressed = try gzip(std.testing.allocator, two, .default);
    defer std.testing.allocator.free(compressed);
    try std.testing.expectError(
        error.TruncatedGzip,
        deps.inspectTarGzip(
            std.testing.allocator,
            compressed[0 .. compressed.len - 1],
            limits(),
        ),
    );
}

test "gzip rejects concatenated members, trailing bytes, and expansion-ratio bombs" {
    const small_tar = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/a", .data = "a" },
    });
    defer std.testing.allocator.free(small_tar);
    const one = try gzip(std.testing.allocator, small_tar, .default);
    defer std.testing.allocator.free(one);

    const concatenated = try std.mem.concat(std.testing.allocator, u8, &.{ one, one });
    defer std.testing.allocator.free(concatenated);
    try std.testing.expectError(
        error.TrailingGzipData,
        deps.inspectTarGzip(std.testing.allocator, concatenated, limits()),
    );

    const trailing = try std.mem.concat(std.testing.allocator, u8, &.{ one, "x" });
    defer std.testing.allocator.free(trailing);
    try std.testing.expectError(
        error.TrailingGzipData,
        deps.inspectTarGzip(std.testing.allocator, trailing, limits()),
    );

    const zeros = try std.testing.allocator.alloc(u8, 64 * 1024);
    defer std.testing.allocator.free(zeros);
    @memset(zeros, 0);
    const bomb_tar = try makeTar(std.testing.allocator, &.{
        .{ .name = "root/zeros.bin", .data = zeros },
    });
    defer std.testing.allocator.free(bomb_tar);
    const bomb = try gzip(std.testing.allocator, bomb_tar, .best);
    defer std.testing.allocator.free(bomb);
    var bounded = limits();
    bounded.max_compression_ratio = 4;
    try std.testing.expectError(
        error.CompressionRatioExceeded,
        deps.inspectTarGzip(std.testing.allocator, bomb, bounded),
    );
}

const ZipEntry = struct {
    name: []const u8,
    data: []const u8,
    method: u16 = 0,
    flags: u16 = 0,
    extra: []const u8 = "",
    external_attributes: u32 = 0,
    descriptor: bool = false,
};

fn makeZip(allocator: std.mem.Allocator, entries: []const ZipEntry) ![]u8 {
    if (entries.len > 8) return error.TooManyEntries;
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    var offsets: [8]u32 = undefined;
    var compressed: [8][]const u8 = undefined;
    var compressed_owned = [_]bool{false} ** 8;
    defer for (compressed[0..entries.len], compressed_owned[0..entries.len]) |bytes, owned| {
        if (owned) allocator.free(@constCast(bytes));
    };

    for (entries, 0..) |entry, index| {
        offsets[index] = @intCast(output.written().len);
        compressed[index] = if (entry.method == 8) block: {
            compressed_owned[index] = true;
            break :block try deflate(allocator, entry.data);
        } else entry.data;
        const crc = std.hash.Crc32.hash(entry.data);
        try output.writer.writeInt(u32, 0x04034b50, .little);
        try output.writer.writeInt(u16, 20, .little);
        try output.writer.writeInt(u16, entry.flags, .little);
        try output.writer.writeInt(u16, entry.method, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u32, if (entry.descriptor) 0 else crc, .little);
        try output.writer.writeInt(u32, if (entry.descriptor) 0 else @as(u32, @intCast(compressed[index].len)), .little);
        try output.writer.writeInt(u32, if (entry.descriptor) 0 else @as(u32, @intCast(entry.data.len)), .little);
        try output.writer.writeInt(u16, @intCast(entry.name.len), .little);
        try output.writer.writeInt(u16, @intCast(entry.extra.len), .little);
        try output.writer.writeAll(entry.name);
        try output.writer.writeAll(entry.extra);
        try output.writer.writeAll(compressed[index]);
        if (entry.descriptor) {
            try output.writer.writeInt(u32, 0x08074b50, .little);
            try output.writer.writeInt(u32, crc, .little);
            try output.writer.writeInt(u32, @intCast(compressed[index].len), .little);
            try output.writer.writeInt(u32, @intCast(entry.data.len), .little);
        }
    }

    const central_offset: u32 = @intCast(output.written().len);
    for (entries, 0..) |entry, index| {
        const crc = std.hash.Crc32.hash(entry.data);
        try output.writer.writeInt(u32, 0x02014b50, .little);
        try output.writer.writeInt(u16, 0x0314, .little);
        try output.writer.writeInt(u16, 20, .little);
        try output.writer.writeInt(u16, entry.flags, .little);
        try output.writer.writeInt(u16, entry.method, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u32, crc, .little);
        try output.writer.writeInt(u32, @intCast(compressed[index].len), .little);
        try output.writer.writeInt(u32, @intCast(entry.data.len), .little);
        try output.writer.writeInt(u16, @intCast(entry.name.len), .little);
        try output.writer.writeInt(u16, @intCast(entry.extra.len), .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u32, entry.external_attributes, .little);
        try output.writer.writeInt(u32, offsets[index], .little);
        try output.writer.writeAll(entry.name);
        try output.writer.writeAll(entry.extra);
    }
    const central_size: u32 = @intCast(output.written().len - central_offset);
    try output.writer.writeInt(u32, 0x06054b50, .little);
    try output.writer.writeInt(u16, 0, .little);
    try output.writer.writeInt(u16, 0, .little);
    try output.writer.writeInt(u16, @intCast(entries.len), .little);
    try output.writer.writeInt(u16, @intCast(entries.len), .little);
    try output.writer.writeInt(u32, central_size, .little);
    try output.writer.writeInt(u32, central_offset, .little);
    try output.writer.writeInt(u16, 0, .little);
    return output.toOwnedSlice();
}

fn deflate(allocator: std.mem.Allocator, plain: []const u8) ![]u8 {
    const capacity = plain.len + 4096;
    const buffer = try allocator.alloc(u8, capacity);
    defer allocator.free(buffer);
    var output = std.Io.Writer.fixed(buffer);
    var history: [std.compress.flate.max_window_len * 2]u8 = undefined;
    var compressor = try std.compress.flate.Compress.init(
        &output,
        &history,
        .raw,
        .best,
    );
    try compressor.writer.writeAll(plain);
    try compressor.finish();
    return allocator.dupe(u8, output.buffered());
}

fn zipPolicy() deps.ZipPolicy {
    const inventory = struct {
        const value = [_]deps.MemberLock{
            .{ .path = "root/a.txt", .size_bytes = 3 },
            .{ .path = "root/b.txt", .size_bytes = 3 },
        };
    }.value;
    return .{
        .max_archive_bytes = 256 * 1024,
        .max_entries = 8,
        .max_member_bytes = 128 * 1024,
        .max_total_bytes = 192 * 1024,
        .max_compression_ratio = 100,
        .allow_data_descriptor = false,
        .allowed_extra_field_ids = &.{},
        .inventory = &inventory,
        .retained_members = &.{},
        .collision_fold = unicode.foldNfd,
    };
}

fn findSignature(bytes: []const u8, signature: u32, occurrence: usize) !usize {
    var encoded: [4]u8 = undefined;
    std.mem.writeInt(u32, &encoded, signature, .little);
    var start: usize = 0;
    var seen: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, start, &encoded)) |index| {
        if (seen == occurrence) return index;
        seen += 1;
        start = index + 1;
    }
    return error.SignatureNotFound;
}

test "restricted ZIP accepts exact stored inventory" {
    const archive = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
        .{ .name = "root/b.txt", .data = "bbb" },
    });
    defer std.testing.allocator.free(archive);
    const summary = try deps.inspectZip(std.testing.allocator, archive, zipPolicy());
    try std.testing.expectEqual(@as(u32, 2), summary.entries);
    try std.testing.expectEqual(@as(u64, 6), summary.content_bytes);
}

test "restricted ZIP rejects local-central name and size disagreement" {
    const archive = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
        .{ .name = "root/b.txt", .data = "bbb" },
    });
    defer std.testing.allocator.free(archive);
    const central = try findSignature(archive, 0x02014b50, 0);
    archive[central + 46 + 5] = 'x';
    try std.testing.expectError(
        error.ZipNameMismatch,
        deps.inspectZip(std.testing.allocator, archive, zipPolicy()),
    );

    archive[central + 46 + 5] = 'a';
    archive[central + 24] = 4;
    try std.testing.expectError(
        error.ZipSizeMismatch,
        deps.inspectZip(std.testing.allocator, archive, zipPolicy()),
    );
}

test "restricted ZIP rejects encryption, flags, methods, descriptors, Zip64, and multi-disk" {
    const encrypted = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa", .flags = 1 },
    });
    defer std.testing.allocator.free(encrypted);
    var policy = zipPolicy();
    policy.inventory = &.{};
    try std.testing.expectError(
        error.UnsupportedZipFlags,
        deps.inspectZip(std.testing.allocator, encrypted, policy),
    );

    const unsupported_method = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa", .method = 99 },
    });
    defer std.testing.allocator.free(unsupported_method);
    try std.testing.expectError(
        error.UnsupportedZipMethod,
        deps.inspectZip(std.testing.allocator, unsupported_method, policy),
    );

    const descriptor = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa", .flags = 0x0008 },
    });
    defer std.testing.allocator.free(descriptor);
    policy.allow_data_descriptor = true;
    try std.testing.expectError(
        error.AmbiguousZipDataDescriptor,
        deps.inspectZip(std.testing.allocator, descriptor, policy),
    );

    const zip64 = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
    });
    defer std.testing.allocator.free(zip64);
    const eocd = zip64.len - 22;
    std.mem.writeInt(u16, zip64[eocd + 8 ..][0..2], 0xffff, .little);
    std.mem.writeInt(u16, zip64[eocd + 10 ..][0..2], 0xffff, .little);
    try std.testing.expectError(
        error.Zip64Unsupported,
        deps.inspectZip(std.testing.allocator, zip64, policy),
    );

    const multi_disk = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
    });
    defer std.testing.allocator.free(multi_disk);
    std.mem.writeInt(u16, multi_disk[multi_disk.len - 18 ..][0..2], 1, .little);
    try std.testing.expectError(
        error.MultiDiskZip,
        deps.inspectZip(std.testing.allocator, multi_disk, policy),
    );
}

test "restricted ZIP accepts only an unambiguous signed descriptor" {
    const valid = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa", .flags = 0x0008, .descriptor = true },
    });
    defer std.testing.allocator.free(valid);
    var policy = zipPolicy();
    policy.inventory = &.{};
    policy.allow_data_descriptor = true;
    _ = try deps.inspectZip(std.testing.allocator, valid, policy);

    const nonzero_local = try std.testing.allocator.dupe(u8, valid);
    defer std.testing.allocator.free(nonzero_local);
    std.mem.writeInt(u32, nonzero_local[14..18], 1, .little);
    try std.testing.expectError(
        error.AmbiguousZipDataDescriptor,
        deps.inspectZip(std.testing.allocator, nonzero_local, policy),
    );
}

test "restricted ZIP rejects unreferenced local bytes and mismatched directory kinds" {
    const archive = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
    });
    defer std.testing.allocator.free(archive);
    const old_eocd = archive.len - 22;
    const old_central: usize = std.mem.readInt(u32, archive[old_eocd + 16 ..][0..4], .little);
    const gapped = try std.testing.allocator.alloc(u8, archive.len + 1);
    defer std.testing.allocator.free(gapped);
    @memcpy(gapped[0..old_central], archive[0..old_central]);
    gapped[old_central] = 0xaa;
    @memcpy(gapped[old_central + 1 ..], archive[old_central..]);
    const new_eocd = gapped.len - 22;
    std.mem.writeInt(u32, gapped[new_eocd + 16 ..][0..4], @intCast(old_central + 1), .little);
    var policy = zipPolicy();
    policy.inventory = &.{};
    try std.testing.expectError(
        error.UnreferencedZipLocalData,
        deps.inspectZip(std.testing.allocator, gapped, policy),
    );

    const wrong_directory = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/", .data = "", .external_attributes = 0x8000_0000 },
    });
    defer std.testing.allocator.free(wrong_directory);
    try std.testing.expectError(
        error.ZipDirectoryAttributeMismatch,
        deps.inspectZip(std.testing.allocator, wrong_directory, policy),
    );

    const missing_dos_directory = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/", .data = "", .external_attributes = 0x4000_0000 },
    });
    defer std.testing.allocator.free(missing_dos_directory);
    try std.testing.expectError(
        error.ZipDirectoryAttributeMismatch,
        deps.inspectZip(std.testing.allocator, missing_dos_directory, policy),
    );

    const file_marked_directory = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "a", .external_attributes = 0x8000_0010 },
    });
    defer std.testing.allocator.free(file_marked_directory);
    try std.testing.expectError(
        error.ZipDirectoryAttributeMismatch,
        deps.inspectZip(std.testing.allocator, file_marked_directory, policy),
    );
}

test "restricted ZIP rejects unsafe names, collisions, links, reparse points, and bad directories" {
    var policy = zipPolicy();
    policy.inventory = &.{};

    for (hostile_archive_member_paths) |path| {
        const archive = try makeZip(std.testing.allocator, &.{.{ .name = path, .data = "x" }});
        defer std.testing.allocator.free(archive);
        try std.testing.expectError(
            error.UnsafeArchivePath,
            deps.inspectZip(std.testing.allocator, archive, policy),
        );
    }

    const traversal = try makeZip(std.testing.allocator, &.{
        .{ .name = "../bad.txt", .data = "x" },
    });
    defer std.testing.allocator.free(traversal);
    try std.testing.expectError(
        error.UnsafeArchivePath,
        deps.inspectZip(std.testing.allocator, traversal, policy),
    );

    const collision = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/Paper.txt", .data = "a" },
        .{ .name = "root/paper.TXT", .data = "b" },
    });
    defer std.testing.allocator.free(collision);
    try std.testing.expectError(
        error.PathCollision,
        deps.inspectZip(std.testing.allocator, collision, policy),
    );

    const unicode_collision = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/caf\u{00e9}.tex", .data = "a" },
        .{ .name = "root/cafe\u{0301}.tex", .data = "b" },
    });
    defer std.testing.allocator.free(unicode_collision);
    try std.testing.expectError(
        error.PathCollision,
        deps.inspectZip(std.testing.allocator, unicode_collision, policy),
    );

    const symlink = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/link", .data = "target", .external_attributes = 0xa0000000 },
    });
    defer std.testing.allocator.free(symlink);
    try std.testing.expectError(
        error.ZipLinkOrSpecialEntry,
        deps.inspectZip(std.testing.allocator, symlink, policy),
    );

    const reparse = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/reparse", .data = "x", .external_attributes = 0x00000400 },
    });
    defer std.testing.allocator.free(reparse);
    try std.testing.expectError(
        error.ZipReparsePoint,
        deps.inspectZip(std.testing.allocator, reparse, policy),
    );

    const nonempty_directory = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/dir/", .data = "x" },
    });
    defer std.testing.allocator.free(nonempty_directory);
    try std.testing.expectError(
        error.InvalidZipDirectory,
        deps.inspectZip(std.testing.allocator, nonempty_directory, policy),
    );

    const nonzero_crc_directory = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/", .data = "", .external_attributes = 0x0000_0010 },
    });
    defer std.testing.allocator.free(nonzero_crc_directory);
    const central = try findSignature(nonzero_crc_directory, 0x02014b50, 0);
    std.mem.writeInt(u32, nonzero_crc_directory[14..18], 1, .little);
    std.mem.writeInt(u32, nonzero_crc_directory[central + 16 ..][0..4], 1, .little);
    try std.testing.expectError(
        error.InvalidZipDirectory,
        deps.inspectZip(std.testing.allocator, nonzero_crc_directory, policy),
    );

    const descriptor_directory = try makeZip(std.testing.allocator, &.{
        .{
            .name = "root/",
            .data = "",
            .flags = 0x0008,
            .external_attributes = 0x0000_0010,
            .descriptor = true,
        },
    });
    defer std.testing.allocator.free(descriptor_directory);
    policy.allow_data_descriptor = true;
    try std.testing.expectError(
        error.InvalidZipDirectory,
        deps.inspectZip(std.testing.allocator, descriptor_directory, policy),
    );
}

test "restricted ZIP rejects malformed, duplicate, and unknown extra fields" {
    var policy = zipPolicy();
    policy.inventory = &.{};
    const timestamp = [_]u8{ 0x55, 0x54, 0x05, 0x00, 0x01, 0, 0, 0, 0 };
    const duplicate_timestamp = timestamp ++ timestamp;

    const malformed = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "a", .extra = &.{0x55} },
    });
    defer std.testing.allocator.free(malformed);
    policy.allowed_extra_field_ids = &.{0x5455};
    try std.testing.expectError(
        error.MalformedZipExtraField,
        deps.inspectZip(std.testing.allocator, malformed, policy),
    );

    const unknown = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "a", .extra = &.{ 0x99, 0x99, 0, 0 } },
    });
    defer std.testing.allocator.free(unknown);
    try std.testing.expectError(
        error.UnknownZipExtraField,
        deps.inspectZip(std.testing.allocator, unknown, policy),
    );

    const duplicate = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "a", .extra = &duplicate_timestamp },
    });
    defer std.testing.allocator.free(duplicate);
    try std.testing.expectError(
        error.DuplicateZipExtraField,
        deps.inspectZip(std.testing.allocator, duplicate, policy),
    );

    const malformed_timestamp = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "a", .extra = &.{ 0x55, 0x54, 0x01, 0, 0x01 } },
    });
    defer std.testing.allocator.free(malformed_timestamp);
    try std.testing.expectError(
        error.MalformedZipExtraField,
        deps.inspectZip(std.testing.allocator, malformed_timestamp, policy),
    );

    var unix_policy = policy;
    unix_policy.allowed_extra_field_ids = &.{0x7875};
    const malformed_unix_owner = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "a", .extra = &.{ 0x75, 0x78, 0x03, 0, 0x02, 0x01, 0x01 } },
    });
    defer std.testing.allocator.free(malformed_unix_owner);
    try std.testing.expectError(
        error.MalformedZipExtraField,
        deps.inspectZip(std.testing.allocator, malformed_unix_owner, unix_policy),
    );

    const mismatched_pair = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "a", .extra = &timestamp },
    });
    defer std.testing.allocator.free(mismatched_pair);
    const central = try findSignature(mismatched_pair, 0x02014b50, 0);
    const central_name_length: usize = std.mem.readInt(u16, mismatched_pair[central + 28 ..][0..2], .little);
    mismatched_pair[central + 46 + central_name_length + 5] = 1;
    try std.testing.expectError(
        error.ZipExtraFieldMismatch,
        deps.inspectZip(std.testing.allocator, mismatched_pair, policy),
    );
}

test "restricted ZIP rejects inventory drift, comments, trailing bytes, CRC, and deflate bombs" {
    const missing = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
    });
    defer std.testing.allocator.free(missing);
    try std.testing.expectError(
        error.ZipInventoryMismatch,
        deps.inspectZip(std.testing.allocator, missing, zipPolicy()),
    );

    const commented = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
    });
    defer std.testing.allocator.free(commented);
    std.mem.writeInt(u16, commented[commented.len - 2 ..][0..2], 1, .little);
    var policy = zipPolicy();
    policy.inventory = &.{};
    try std.testing.expectError(
        error.ZipCommentOrTrailingData,
        deps.inspectZip(std.testing.allocator, commented, policy),
    );

    const clean = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
    });
    defer std.testing.allocator.free(clean);
    const trailing = try std.mem.concat(std.testing.allocator, u8, &.{ clean, "x" });
    defer std.testing.allocator.free(trailing);
    try std.testing.expectError(
        error.ZipCommentOrTrailingData,
        deps.inspectZip(std.testing.allocator, trailing, policy),
    );

    clean[30 + "root/a.txt".len] ^= 1;
    try std.testing.expectError(
        error.ZipCrcMismatch,
        deps.inspectZip(std.testing.allocator, clean, policy),
    );

    const zeros = try std.testing.allocator.alloc(u8, 64 * 1024);
    defer std.testing.allocator.free(zeros);
    @memset(zeros, 0);
    const bomb = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/zeros.bin", .data = zeros, .method = 8 },
    });
    defer std.testing.allocator.free(bomb);
    policy.max_compression_ratio = 4;
    try std.testing.expectError(
        error.CompressionRatioExceeded,
        deps.inspectZip(std.testing.allocator, bomb, policy),
    );

    const invalid_deflate = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/data.bin", .data = "compress me", .method = 8 },
    });
    defer std.testing.allocator.free(invalid_deflate);
    invalid_deflate[30 + "root/data.bin".len] = 0x07;
    policy.max_compression_ratio = 100;
    try std.testing.expectError(
        error.InvalidZipDeflate,
        deps.inspectZip(std.testing.allocator, invalid_deflate, policy),
    );
}

test "restricted ZIP rejects duplicate local records and retained-member digest drift" {
    const duplicate_record = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
        .{ .name = "root/b.txt", .data = "bbb" },
    });
    defer std.testing.allocator.free(duplicate_record);
    const second_central = try findSignature(duplicate_record, 0x02014b50, 1);
    std.mem.writeInt(u32, duplicate_record[second_central + 42 ..][0..4], 0, .little);
    var policy = zipPolicy();
    policy.inventory = &.{};
    try std.testing.expectError(
        error.DuplicateZipRecord,
        deps.inspectZip(std.testing.allocator, duplicate_record, policy),
    );

    const digest_drift = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
    });
    defer std.testing.allocator.free(digest_drift);
    const retained = [_]deps.MemberLock{.{
        .path = "root/a.txt",
        .size_bytes = 3,
        .sha256 = "0000000000000000000000000000000000000000000000000000000000000000",
    }};
    policy.retained_members = &retained;
    try std.testing.expectError(
        error.DigestMismatch,
        deps.inspectZip(std.testing.allocator, digest_drift, policy),
    );
}

fn exerciseTarGzipInspection(
    allocator: std.mem.Allocator,
    compressed: []const u8,
) anyerror!void {
    const summary = try deps.inspectTarGzip(allocator, compressed, limits());
    try std.testing.expectEqual(@as(u32, 1), summary.regular_files);
    try std.testing.expectEqual(@as(u64, 3), summary.content_bytes);
}

fn exerciseCanonicalTreeDigest(
    allocator: std.mem.Allocator,
    compressed: []const u8,
) anyerror!void {
    const digest = try deps.canonicalTreeDigestTarGzip(
        allocator,
        compressed,
        limits(),
        1,
    );
    try std.testing.expect(!std.mem.allEqual(u8, &digest, 0));
}

fn exerciseZipInspection(
    allocator: std.mem.Allocator,
    archive: []const u8,
) anyerror!void {
    const summary = try deps.inspectZip(allocator, archive, zipPolicy());
    try std.testing.expectEqual(@as(u32, 2), summary.regular_files);
    try std.testing.expectEqual(@as(u64, 6), summary.content_bytes);
}

fn checkArchiveAllocationsThroughOnePast(
    comptime exercise: anytype,
    label: []const u8,
    input: []const u8,
) !usize {
    const max_allocations = 16_384;
    for (0..max_allocations) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        exercise(failing.allocator(), input) catch |err| {
            if (err != error.OutOfMemory) {
                std.debug.print(
                    "archive-allocation-campaign={s} fail-index={d} unexpected-error={s}\n",
                    .{ label, fail_index, @errorName(err) },
                );
                return err;
            }
            if (!failing.has_induced_failure) return error.UnexpectedOutOfMemory;
            if (failing.allocated_bytes != failing.freed_bytes) {
                return error.MemoryLeakDetected;
            }
            continue;
        };
        if (failing.has_induced_failure) return error.SwallowedOutOfMemoryError;
        if (failing.allocated_bytes != failing.freed_bytes) {
            return error.MemoryLeakDetected;
        }
        return fail_index;
    }
    return error.AllocationCampaignLimitExceeded;
}

fn checkArchiveParserAllocationFailures() !void {
    const tar = try makeTar(std.testing.allocator, &.{.{
        .name = "root/file.txt",
        .data = "abc",
    }});
    defer std.testing.allocator.free(tar);
    const compressed = try gzip(std.testing.allocator, tar, .default);
    defer std.testing.allocator.free(compressed);
    const zip = try makeZip(std.testing.allocator, &.{
        .{ .name = "root/a.txt", .data = "aaa" },
        .{ .name = "root/b.txt", .data = "bbb" },
    });
    defer std.testing.allocator.free(zip);

    const tar_count = try checkArchiveAllocationsThroughOnePast(
        exerciseTarGzipInspection,
        "tar-gzip",
        compressed,
    );
    const canonical_count = try checkArchiveAllocationsThroughOnePast(
        exerciseCanonicalTreeDigest,
        "canonical-tree",
        compressed,
    );
    const zip_count = try checkArchiveAllocationsThroughOnePast(
        exerciseZipInspection,
        "zip",
        zip,
    );
    try std.testing.expectEqual(@as(usize, 16), tar_count);
    try std.testing.expectEqual(@as(usize, 18), canonical_count);
    try std.testing.expectEqual(@as(usize, 29), zip_count);
}

test "archive parsers release every allocation through and one past success" {
    try checkArchiveParserAllocationFailures();
}

fn materializationArtifact(
    id: []const u8,
    format: deps.ArchiveFormat,
    archive_size: usize,
    inventory: []const deps.MemberLock,
) deps.Artifact {
    return .{
        .id = id,
        .version = "fixture-v1",
        .purpose = "allocation fixture",
        .source_url = "https://example.test/source",
        .license_spdx = "MIT",
        .license_url = "https://example.test/license",
        .url = "https://example.test/archive",
        .allowed_path_prefix = "/archive",
        .integrity = .byte_archive,
        .archive_format = format,
        .archive_root = if (format == .direct_file) "" else "root/",
        .archive_size_bytes = archive_size,
        .archive_sha256 = "0000000000000000000000000000000000000000000000000000000000000000",
        .expected_entries = 1,
        .expected_regular_files = 1,
        .download_limit_bytes = 256 * 1024,
        .expanded_limit_bytes = 256 * 1024,
        .expected_expanded_bytes = 3,
        .inventory = inventory,
        .dependencies = &.{},
        .build_switches = &.{},
    };
}

fn expectDirectoryEmpty(dir: std.Io.Dir) !void {
    var iterator = dir.iterate();
    try std.testing.expect(try iterator.next(std.testing.io) == null);
}

fn checkMaterializationAllocationsThroughOnePast(
    label: []const u8,
    artifact: deps.Artifact,
    archive: []const u8,
) !usize {
    const max_allocations = 16_384;
    for (0..max_allocations) |fail_index| {
        var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
        defer temp.cleanup();
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        const result = deps.materializeArtifact(
            failing.allocator(),
            std.testing.io,
            artifact,
            archive,
            temp.dir,
            unicode.foldNfd,
        ) catch |err| {
            if (err != error.OutOfMemory) {
                std.debug.print(
                    "materialization-allocation-campaign={s} fail-index={d} unexpected-error={s}\n",
                    .{ label, fail_index, @errorName(err) },
                );
                return err;
            }
            if (!failing.has_induced_failure) return error.UnexpectedOutOfMemory;
            if (failing.allocated_bytes != failing.freed_bytes) {
                return error.MemoryLeakDetected;
            }
            try expectDirectoryEmpty(temp.dir);
            continue;
        };
        if (failing.has_induced_failure) return error.SwallowedOutOfMemoryError;
        if (failing.allocated_bytes != failing.freed_bytes) {
            return error.MemoryLeakDetected;
        }
        try std.testing.expectEqual(@as(u32, 1), result.payload_files);
        try std.testing.expectEqual(@as(u64, 3), result.payload_bytes);
        return fail_index;
    }
    return error.AllocationCampaignLimitExceeded;
}

fn checkArchiveMaterializerAllocationFailures() !void {
    const tar = try makeTar(std.testing.allocator, &.{.{
        .name = "root/file.txt",
        .data = "abc",
    }});
    defer std.testing.allocator.free(tar);
    const compressed = try gzip(std.testing.allocator, tar, .default);
    defer std.testing.allocator.free(compressed);
    const zip = try makeZip(std.testing.allocator, &.{.{
        .name = "root/file.txt",
        .data = "abc",
    }});
    defer std.testing.allocator.free(zip);
    const zip_inventory = [_]deps.MemberLock{.{
        .path = "root/file.txt",
        .size_bytes = 3,
    }};

    const direct_count = try checkMaterializationAllocationsThroughOnePast(
        "direct-file",
        materializationArtifact("presentmon", .direct_file, 3, &.{}),
        "abc",
    );
    const tar_count = try checkMaterializationAllocationsThroughOnePast(
        "tar-gzip",
        materializationArtifact("fixture", .tar_gzip, compressed.len, &.{}),
        compressed,
    );
    const zip_count = try checkMaterializationAllocationsThroughOnePast(
        "zip",
        materializationArtifact("fixture", .restricted_zip, zip.len, &zip_inventory),
        zip,
    );
    try std.testing.expectEqual(@as(usize, 2), direct_count);
    try std.testing.expectEqual(@as(usize, 20), tar_count);
    try std.testing.expectEqual(@as(usize, 18), zip_count);
}

fn checkMaterializedTreeHashAllocationFailures() !void {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();
    try temp.dir.writeFile(io, .{ .sub_path = "paper.tex", .data = "abc" });

    const max_allocations = 16_384;
    for (0..max_allocations) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        const result = deps.hashMaterializedDirectory(
            failing.allocator(),
            io,
            temp.dir,
            256 * 1024,
        ) catch |err| {
            if (err != error.OutOfMemory) return err;
            if (!failing.has_induced_failure) return error.UnexpectedOutOfMemory;
            if (failing.allocated_bytes != failing.freed_bytes) {
                return error.MemoryLeakDetected;
            }
            const retained = try temp.dir.readFileAlloc(
                io,
                "paper.tex",
                std.testing.allocator,
                .limited(4),
            );
            defer std.testing.allocator.free(retained);
            try std.testing.expectEqualStrings("abc", retained);
            continue;
        };
        if (failing.has_induced_failure) return error.SwallowedOutOfMemoryError;
        if (failing.allocated_bytes != failing.freed_bytes) {
            return error.MemoryLeakDetected;
        }
        try std.testing.expectEqual(@as(u32, 1), result.files);
        try std.testing.expectEqual(@as(u64, 3), result.bytes);
        try std.testing.expectEqual(@as(usize, 4), fail_index);
        return;
    }
    return error.AllocationCampaignLimitExceeded;
}

fn expectCanonicalMaterializationError(
    expected_error: anyerror,
    artifact: deps.Artifact,
    entries: []const TarEntry,
) !void {
    const tar = try makeTar(std.testing.allocator, entries);
    defer std.testing.allocator.free(tar);
    const compressed = try gzip(std.testing.allocator, tar, .default);
    defer std.testing.allocator.free(compressed);
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();
    try std.testing.expectError(
        expected_error,
        deps.materializeArtifact(
            std.testing.allocator,
            std.testing.io,
            artifact,
            compressed,
            temp.dir,
            unicode.foldNfd,
        ),
    );
    try expectDirectoryEmpty(temp.dir);
}

fn checkCanonicalTreeMaterializationGate() !void {
    const baseline_tar = try makeTar(std.testing.allocator, &.{.{
        .name = "root/file.txt",
        .data = "abc",
    }});
    defer std.testing.allocator.free(baseline_tar);
    const baseline_compressed = try gzip(std.testing.allocator, baseline_tar, .default);
    defer std.testing.allocator.free(baseline_compressed);
    const digest = try deps.canonicalTreeDigestTarGzip(
        std.testing.allocator,
        baseline_compressed,
        limits(),
        1,
    );
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    var artifact = materializationArtifact(
        "fixture",
        .tar_gzip,
        baseline_compressed.len,
        &.{},
    );
    artifact.integrity = .canonical_tree;
    artifact.archive_sha256 = null;
    artifact.canonical_tree_sha256 = &digest_hex;

    var valid_destination = std.testing.tmpDir(.{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer valid_destination.cleanup();
    const valid = try deps.materializeArtifact(
        std.testing.allocator,
        std.testing.io,
        artifact,
        baseline_compressed,
        valid_destination.dir,
        unicode.foldNfd,
    );
    try std.testing.expectEqual(@as(u32, 1), valid.payload_files);
    try std.testing.expectEqual(@as(u64, 3), valid.payload_bytes);

    try expectCanonicalMaterializationError(
        error.CanonicalTreeDigestMismatch,
        artifact,
        &.{.{ .name = "root/fyle.txt", .data = "abc" }},
    );
    try expectCanonicalMaterializationError(
        error.CanonicalTreeDigestMismatch,
        artifact,
        &.{.{ .name = "root/file.txt", .data = "abcd" }},
    );
    try expectCanonicalMaterializationError(
        error.PathCollision,
        artifact,
        &.{
            .{ .name = "root/file.txt", .data = "abc" },
            .{ .name = "root/file.txt", .data = "def" },
        },
    );
    try expectCanonicalMaterializationError(
        error.UnsupportedTarEntry,
        artifact,
        &.{.{ .name = "root/link", .kind = '2' }},
    );
    try expectCanonicalMaterializationError(
        error.UnsafeArchivePath,
        artifact,
        &.{.{ .name = "root/\x1fhidden", .data = "abc" }},
    );
    try expectCanonicalMaterializationError(
        error.PathCollision,
        artifact,
        &.{
            .{ .name = "root/caf\u{00e9}.tex", .data = "a" },
            .{ .name = "root/cafe\u{0301}.tex", .data = "b" },
        },
    );
}

test "single-member archive materializers release every allocation through success" {
    try checkArchiveMaterializerAllocationFailures();
}

test "materialized tree hashing releases every allocation without mutation" {
    try checkMaterializedTreeHashAllocationFailures();
}

test "canonical-tree materialization rejects drift before destination mutation" {
    try checkCanonicalTreeMaterializationGate();
}
