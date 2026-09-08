const std = @import("std");
const lexer = @import("lexer");

fn hasStyle(tokens: []const lexer.Token, style: lexer.Style) bool {
    for (tokens) |token| {
        if (token.style == style) return true;
    }
    return false;
}

fn hasKind(tokens: []const lexer.Token, kind: lexer.TokenKind) bool {
    for (tokens) |token| {
        if (token.kind == kind) return true;
    }
    return false;
}

fn containsText(input: []const u8, tokens: []const lexer.Token, text: []const u8, style: lexer.Style) bool {
    for (tokens) |token| {
        if (token.style == style and std.mem.eql(u8, input[token.start..token.end], text)) return true;
    }
    return false;
}

fn containsFragment(input: []const u8, tokens: []const lexer.Token, fragment: []const u8, style: lexer.Style) bool {
    for (tokens) |token| {
        if (token.style == style and std.mem.indexOf(u8, input[token.start..token.end], fragment) != null) return true;
    }
    return false;
}

fn tokenText(input: []const u8, token: lexer.Token) []const u8 {
    return input[token.start..token.end];
}

fn expectPartition(input: []const u8, tokens: []const lexer.Token) !void {
    var cursor: usize = 0;
    for (tokens) |token| {
        try std.testing.expectEqual(cursor, token.start);
        try std.testing.expect(token.end > token.start);
        try std.testing.expect(token.end <= input.len);
        cursor = token.end;
    }
    try std.testing.expectEqual(input.len, cursor);
}

fn lexInChunks(
    allocator: std.mem.Allocator,
    language: lexer.Language,
    input: []const u8,
    chunk_size: usize,
) ![]lexer.Token {
    var state = lexer.State.init(language);
    var all: std.ArrayList(lexer.Token) = .empty;
    errdefer all.deinit(allocator);

    var offset: usize = 0;
    while (offset < input.len) {
        const end = @min(offset + chunk_size, input.len);
        const chunk = try state.scanChunk(allocator, input[offset..end], end == input.len);
        defer allocator.free(chunk);
        try all.appendSlice(allocator, chunk);
        offset = end;
    }
    if (input.len == 0) {
        const chunk = try state.scanChunk(allocator, input, true);
        defer allocator.free(chunk);
        try all.appendSlice(allocator, chunk);
    }
    return all.toOwnedSlice(allocator);
}

test "LaTeX lexer styles commands comments math environments and semantic arguments" {
    const input =
        "\\documentclass{article}\n" ++
        "% visible comment\n" ++
        "escaped \\% stays text\n" ++
        "$a+b$\n" ++
        "\\begin{equation}x^2 + y^2 = z^2\\end{equation}\n" ++
        "\\begin{verbatim}\n% keep this\\n\\end{verbatim}\n" ++
        "\\cite[see p. 4]{smith2024,nguyen2025}\n" ++
        "\\label{eq:one} \\ref{eq:one}\n" ++
        "\\section[Short]{Long}";

    const tokens = try lexer.lex(std.testing.allocator, .latex, input);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(hasKind(tokens, .command));
    try std.testing.expect(hasStyle(tokens, .comment));
    try std.testing.expect(hasKind(tokens, .math_delimiter));
    try std.testing.expect(hasStyle(tokens, .math));
    try std.testing.expect(hasStyle(tokens, .verbatim));
    try std.testing.expect(hasStyle(tokens, .environment));
    try std.testing.expect(hasStyle(tokens, .citation));
    try std.testing.expect(hasStyle(tokens, .label));
    try std.testing.expect(hasStyle(tokens, .reference));
    try std.testing.expect(hasStyle(tokens, .optional_argument));
    try std.testing.expect(containsText(input, tokens, "% visible comment", .comment));
    try std.testing.expect(!containsText(input, tokens, "% stays text", .comment));
    try std.testing.expect(containsText(input, tokens, "smith2024,nguyen2025", .citation));
    try std.testing.expect(containsText(input, tokens, "eq:one", .label));
    try std.testing.expect(containsText(input, tokens, "eq:one", .reference));
    try expectPartition(input, tokens);
}

test "chunked LaTeX lexing is equivalent at every byte boundary" {
    const input =
        "Tiếng Việt e\u{301} 😀 \\cite[trang]{một,ref}\r\n" ++
        "\\begin{equation}\nα + β = γ\\end{equation}\n" ++
        "\\begin{verbatim}\n\\% % [not syntax]\n\\end{verbatim}";

    const full = try lexer.lex(std.testing.allocator, .latex, input);
    defer std.testing.allocator.free(full);

    var size: usize = 1;
    while (size <= input.len + 1) : (size += 1) {
        const chunked = try lexInChunks(std.testing.allocator, .latex, input, size);
        defer std.testing.allocator.free(chunked);
        try std.testing.expectEqualDeep(full, chunked);
    }
}

test "math command delimiters, raw comment environments, and starred citations are stable" {
    const input =
        "\\(...\\) $$x+y$$ \\[z\\]\n" ++
        "\\begin{comment}\ninside % is data\n\\end{comment}\n" ++
        "\\cite*{starred-key}";

    const tokens = try lexer.lex(std.testing.allocator, .latex, input);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(containsText(input, tokens, "starred-key", .citation));
    try std.testing.expect(containsFragment(input, tokens, "inside % is data", .comment));
    try std.testing.expect(hasStyle(tokens, .math_delimiter));
    try expectPartition(input, tokens);

    const chunked = try lexInChunks(std.testing.allocator, .latex, input, 1);
    defer std.testing.allocator.free(chunked);
    try std.testing.expectEqualDeep(tokens, chunked);
}

test "BibTeX lexer styles entries fields strings and comment blocks" {
    const input =
        "% file comment\n" ++
        "@string{abbr = \"J. Test\"}\n" ++
        "@article{smith2024,\n" ++
        "  author = {Nguyễn Văn A},\n" ++
        "  title = \"A #1\",\n" ++
        "  year = 2026\n" ++
        "}\n" ++
        "@online{web2026, url = {https://example.test}}\n" ++
        "@misc(key, note = {a) b})\n" ++
        "@comment{generated note {with nesting}}";

    const tokens = try lexer.lex(std.testing.allocator, .bibtex, input);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(hasStyle(tokens, .bib_entry));
    try std.testing.expect(hasStyle(tokens, .bib_field));
    try std.testing.expect(hasStyle(tokens, .bib_string));
    try std.testing.expect(hasStyle(tokens, .bib_comment));
    try std.testing.expect(containsText(input, tokens, "author", .bib_field));
    try std.testing.expect(containsText(input, tokens, "J. Test", .bib_string));
    try std.testing.expect(containsText(input, tokens, "@online", .bib_entry));
    try std.testing.expect(containsText(input, tokens, "a) b", .bib_string));
    try std.testing.expect(containsText(input, tokens, "generated note ", .bib_comment));
    try expectPartition(input, tokens);

    const chunked = try lexInChunks(std.testing.allocator, .bibtex, input, 3);
    defer std.testing.allocator.free(chunked);
    try std.testing.expectEqualDeep(tokens, chunked);
}

test "invalid UTF-8 is rejected without replacement" {
    const invalid = [_]u8{ 'a', 0xc3, 0x28, 'b' };
    try std.testing.expectError(error.InvalidUtf8, lexer.lex(std.testing.allocator, .latex, &invalid));

    var state = lexer.State.init(.latex);
    const first = try state.scanChunk(std.testing.allocator, invalid[0..2], false);
    defer std.testing.allocator.free(first);
    try std.testing.expectError(error.InvalidUtf8, state.scanChunk(std.testing.allocator, invalid[2..], true));

    const nul = [_]u8{ 'a', 0, 'b' };
    try std.testing.expectError(error.EmbeddedNul, lexer.lex(std.testing.allocator, .latex, &nul));
}

test "malformed input is bounded and long lines remain one deterministic run" {
    const malformed = "$x + y";
    const malformed_tokens = try lexer.lex(std.testing.allocator, .latex, malformed);
    defer std.testing.allocator.free(malformed_tokens);
    try std.testing.expect(hasStyle(malformed_tokens, .malformed));

    const malformed_optional = try lexer.lex(std.testing.allocator, .latex, "[unfinished");
    defer std.testing.allocator.free(malformed_optional);
    try std.testing.expect(hasStyle(malformed_optional, .malformed));

    const malformed_bib = try lexer.lex(std.testing.allocator, .bibtex, "@article{k, title = \"unfinished");
    defer std.testing.allocator.free(malformed_bib);
    try std.testing.expect(hasStyle(malformed_bib, .malformed));

    const malformed_argument = try lexer.lex(std.testing.allocator, .latex, "\\cite{unfinished");
    defer std.testing.allocator.free(malformed_argument);
    try std.testing.expect(hasStyle(malformed_argument, .malformed));

    const length = 256 * 1024;
    const long_line = try std.testing.allocator.alloc(u8, length);
    defer std.testing.allocator.free(long_line);
    @memset(long_line, 'x');

    const tokens = try lexer.lex(std.testing.allocator, .latex, long_line);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(@as(usize, length), tokens[0].end - tokens[0].start);
    try std.testing.expectEqualStrings("x", tokenText(long_line, tokens[0])[0..1]);
}
