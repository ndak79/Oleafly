const std = @import("std");
const capture = @import("capture_contract");

fn validLayout() capture.PixelLayout {
    return .{
        .width = 4,
        .height = 3,
        .stride = 20,
        .channel_order = .bgra8,
    };
}

fn validMetadata() capture.FrameMetadata {
    return .{
        .layout = validLayout(),
        .rotation = 0,
        .crop = .{ .left = 1, .top = 1, .right = 3, .bottom = 3 },
        .crop_space = .physical,
        .dpi = 144,
        .last_present_qpc = 200,
        .accumulated_frames = 0,
        .protected_content = false,
    };
}

test "known BGRA fixture validates stride and preserves deterministic raw/encoded digests" {
    const layout = validLayout();
    try layout.validate();
    try std.testing.expectEqual(@as(u32, 16), try layout.row_bytes());
    try std.testing.expectEqual(@as(usize, 60), try layout.byte_length());
    try std.testing.expectEqual(@as([4]u8, .{ 34, 107, 180, 255 }), capture.known_pixel(1, 1));

    const pixels = try capture.make_known_pixels(std.testing.allocator, layout);
    defer std.testing.allocator.free(pixels);
    try capture.validate_pixels(layout, pixels);

    const raw_digest = capture.raw_digest(pixels);
    const encoded = try capture.encode_fixture(std.testing.allocator, validMetadata(), pixels);
    defer std.testing.allocator.free(encoded);
    const encoded_again = try capture.encode_fixture(std.testing.allocator, validMetadata(), pixels);
    defer std.testing.allocator.free(encoded_again);
    try std.testing.expectEqualSlices(u8, encoded, encoded_again);
    try std.testing.expectEqual(capture.encoded_digest(encoded), capture.encoded_digest(encoded_again));

    var decoded = try capture.decode_fixture(std.testing.allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqual(validMetadata(), decoded.metadata);
    try std.testing.expectEqualSlices(u8, pixels, decoded.pixels);
    try std.testing.expectEqual(raw_digest, decoded.raw_digest);
    try std.testing.expectEqual(raw_digest, capture.raw_digest(decoded.pixels));
}

test "malformed stride, channel order, dimensions, and byte length are rejected" {
    try std.testing.expectError(error.InvalidStride, (capture.PixelLayout{
        .width = 4,
        .height = 3,
        .stride = 15,
        .channel_order = .bgra8,
    }).validate());
    try std.testing.expectError(error.InvalidStride, (capture.PixelLayout{
        .width = 4,
        .height = 3,
        .stride = 12,
        .channel_order = .bgra8,
    }).validate());
    try std.testing.expectError(error.InvalidChannelOrder, (capture.PixelLayout{
        .width = 4,
        .height = 3,
        .stride = 16,
        .channel_order = .rgba8,
    }).validate());
    try std.testing.expectError(error.InvalidDimensions, (capture.PixelLayout{
        .width = 0,
        .height = 3,
        .stride = 16,
        .channel_order = .bgra8,
    }).validate());

    const layout = validLayout();
    var short_pixels: [59]u8 = undefined;
    try std.testing.expectError(error.InvalidPixelBytes, capture.validate_pixels(layout, &short_pixels));

    var no_clock = validMetadata();
    no_clock.last_present_qpc = 0;
    try std.testing.expectError(error.InvalidMetadata, capture.validate_metadata(no_clock));
}

test "rotation, physical crop, and DPI conversion reject malformed or virtualized coordinates" {
    const layout = validLayout();
    try std.testing.expectEqual(capture.Extent{ .width = 3, .height = 4 }, try capture.rotated_extent(layout, 90));
    try std.testing.expectEqual(capture.Extent{ .width = 4, .height = 3 }, try capture.rotated_extent(layout, 180));
    try std.testing.expectError(error.InvalidRotation, capture.rotated_extent(layout, 45));

    try capture.validate_crop(layout, 90, .{ .left = 0, .top = 0, .right = 3, .bottom = 4 }, .physical);
    try std.testing.expectError(error.CropOutOfBounds, capture.validate_crop(
        layout,
        90,
        .{ .left = 0, .top = 0, .right = 4, .bottom = 4 },
        .physical,
    ));
    try std.testing.expectError(error.InvalidCrop, capture.validate_crop(
        layout,
        0,
        .{ .left = 2, .top = 1, .right = 2, .bottom = 2 },
        .physical,
    ));
    try std.testing.expectError(error.VirtualizedCrop, capture.validate_crop(
        layout,
        0,
        .{ .left = 0, .top = 0, .right = 4, .bottom = 3 },
        .logical,
    ));

    try std.testing.expectEqual(@as(u32, 150), try capture.dip_to_physical(100, 144));
    try std.testing.expectError(error.InvalidDpi, capture.dip_to_physical(100, 0));
    try std.testing.expectError(error.InvalidDpi, capture.dip_to_physical(100, 97));
    try std.testing.expectError(error.InvalidDpi, capture.dip_to_physical(std.math.maxInt(u32), 192));
}

test "stale QPC, accumulated frames, protected content, and missing frames are typed outcomes" {
    var stale = validMetadata();
    stale.last_present_qpc = 99;
    var outcome = try capture.classify(.{
        .status = .acquired,
        .frame = stale,
        .observed_qpc = 100,
        .deadline_qpc = 500,
        .duplication_generation = 1,
    }, 100, 1);
    switch (outcome) {
        .stale_qpc => |value| {
            try std.testing.expectEqual(@as(u64, 99), value.frame_qpc);
            try std.testing.expectEqual(@as(u64, 100), value.marker_qpc);
        },
        else => return error.ExpectedStaleQpc,
    }

    var equal_marker = validMetadata();
    equal_marker.last_present_qpc = 100;
    outcome = try capture.classify(.{ .status = .acquired, .frame = equal_marker, .observed_qpc = 100, .deadline_qpc = 500, .duplication_generation = 1 }, 100, 1);
    switch (outcome) {
        .stale_qpc => {},
        else => return error.ExpectedEqualMarkerStale,
    }

    var accumulated = validMetadata();
    accumulated.accumulated_frames = 2;
    outcome = try capture.classify(.{ .status = .acquired, .frame = accumulated, .observed_qpc = 100, .deadline_qpc = 500, .duplication_generation = 1 }, 100, 1);
    switch (outcome) {
        .accumulated_frames => |count| try std.testing.expectEqual(@as(u32, 2), count),
        else => return error.ExpectedAccumulatedFrames,
    }

    var single_update = validMetadata();
    single_update.accumulated_frames = 1;
    outcome = try capture.classify(.{ .status = .acquired, .frame = single_update, .observed_qpc = 100, .deadline_qpc = 500, .duplication_generation = 1 }, 100, 1);
    try std.testing.expectEqual(capture.CaptureOutcome.accepted, outcome);

    var protected = validMetadata();
    protected.protected_content = true;
    outcome = try capture.classify(.{ .status = .acquired, .frame = protected, .observed_qpc = 100, .deadline_qpc = 500, .duplication_generation = 1 }, 100, 1);
    switch (outcome) {
        .protected_content => {},
        else => return error.ExpectedProtectedContent,
    }

    try std.testing.expectError(error.MissingFrame, capture.classify(.{ .status = .acquired, .observed_qpc = 100, .deadline_qpc = 500 }, 100, 1));
    try std.testing.expectError(error.StaleGeneration, capture.classify(.{ .status = .acquired, .frame = validMetadata(), .observed_qpc = 100, .deadline_qpc = 500, .duplication_generation = 2 }, 100, 1));
    try std.testing.expectError(error.StaleGeneration, capture.classify(.{ .status = .acquired, .frame = validMetadata(), .observed_qpc = 100, .deadline_qpc = 500 }, 100, 1));

    var invalid_frame = validMetadata();
    invalid_frame.dpi = 97;
    try std.testing.expectError(error.InvalidDpi, capture.classify(.{ .status = .acquired, .frame = invalid_frame, .observed_qpc = 100, .deadline_qpc = 500, .duplication_generation = 1 }, 100, 1));
}

test "finite waits and cancellation never become an unbounded wait" {
    const ready = try capture.finite_wait(100, 150);
    switch (ready) {
        .ready => |value| try std.testing.expectEqual(@as(u64, 50), value.remaining_qpc),
        else => return error.ExpectedReadyWait,
    }

    const timeout = try capture.finite_wait(150, 150);
    switch (timeout) {
        .timeout => |value| {
            try std.testing.expectEqual(@as(u64, 150), value.deadline_qpc);
            try std.testing.expectEqual(@as(u64, 150), value.observed_qpc);
        },
        else => return error.ExpectedTimeout,
    }
    try std.testing.expectError(error.InvalidDeadline, capture.finite_wait(1, 0));
    try std.testing.expectError(error.InvalidDeadline, capture.finite_wait(0, 1));
    try std.testing.expectError(error.InvalidDeadline, capture.classify(.{
        .status = .timeout,
        .observed_qpc = 10,
        .deadline_qpc = 100,
    }, 0, 1));
    try std.testing.expectError(error.InvalidDeadline, capture.classify(.{
        .status = .timeout,
        .observed_qpc = 0,
        .deadline_qpc = 100,
    }, 0, 1));
    try std.testing.expectError(error.InvalidDeadline, capture.classify(.{
        .status = .acquired,
        .frame = validMetadata(),
        .observed_qpc = 501,
        .deadline_qpc = 500,
        .duplication_generation = 1,
    }, 0, 1));
    try std.testing.expectError(error.InvalidMetadata, capture.classify(.{
        .status = .acquired,
        .frame = validMetadata(),
        .observed_qpc = 100,
        .deadline_qpc = 500,
        .duplication_generation = 1,
    }, 0, 1));

    const cancelled = try capture.classify(.{
        .status = .cancelled,
        .observed_qpc = 101,
        .deadline_qpc = 500,
    }, 100, 1);
    switch (cancelled) {
        .cancelled => {},
        else => return error.ExpectedCancellation,
    }
}

test "access loss returns a typed outcome and requires a fresh duplication generation" {
    var session = capture.DuplicationSession.init();
    const generation = session.generation;
    const outcome = try capture.classify(.{
        .status = .access_lost,
        .duplication_generation = generation,
    }, 0, generation);
    switch (outcome) {
        .access_lost => {},
        else => return error.ExpectedAccessLost,
    }

    session.mark_access_lost();
    try std.testing.expectError(error.AccessLost, session.require_generation(generation));
    const recreated = try session.recreate_after_access_loss();
    try std.testing.expectEqual(generation + 1, recreated);
    try session.require_generation(recreated);
    try std.testing.expectError(error.StaleGeneration, session.require_generation(generation));
    try std.testing.expectError(error.RecreationNotRequired, session.recreate_after_access_loss());
}

test "raw and encoded digests change when pixels or metadata change" {
    const layout = validLayout();
    const pixels = try capture.make_known_pixels(std.testing.allocator, layout);
    defer std.testing.allocator.free(pixels);

    const encoded = try capture.encode_fixture(std.testing.allocator, validMetadata(), pixels);
    defer std.testing.allocator.free(encoded);
    var changed_pixels = try std.testing.allocator.dupe(u8, pixels);
    defer std.testing.allocator.free(changed_pixels);
    changed_pixels[0] +%= 1;
    const changed_encoded = try capture.encode_fixture(std.testing.allocator, validMetadata(), changed_pixels);
    defer std.testing.allocator.free(changed_encoded);
    try std.testing.expect(!std.mem.eql(u8, &capture.raw_digest(pixels), &capture.raw_digest(changed_pixels)));
    try std.testing.expect(!std.mem.eql(u8, &capture.encoded_digest(encoded), &capture.encoded_digest(changed_encoded)));

    var changed_metadata = validMetadata();
    changed_metadata.rotation = 90;
    changed_metadata.crop = .{ .left = 0, .top = 0, .right = 3, .bottom = 4 };
    const changed_metadata_encoded = try capture.encode_fixture(std.testing.allocator, changed_metadata, pixels);
    defer std.testing.allocator.free(changed_metadata_encoded);
    try std.testing.expect(!std.mem.eql(u8, &capture.encoded_digest(encoded), &capture.encoded_digest(changed_metadata_encoded)));
}

test "fixture decoder rejects encoded digest drift and truncation" {
    const pixels = try capture.make_known_pixels(std.testing.allocator, validLayout());
    defer std.testing.allocator.free(pixels);
    const encoded = try capture.encode_fixture(std.testing.allocator, validMetadata(), pixels);
    defer std.testing.allocator.free(encoded);

    var digest_drift = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(digest_drift);
    // Mutate a pixel byte, keeping the declared frame length structurally
    // valid so the decoder reports an integrity failure rather than a shape
    // failure.
    digest_drift[80] ^= 0x01;
    try std.testing.expectError(error.DigestMismatch, capture.decode_fixture(std.testing.allocator, digest_drift));

    try std.testing.expectError(error.InvalidFixture, capture.decode_fixture(std.testing.allocator, encoded[0 .. encoded.len - 1]));
}
