const std = @import("std");

pub const Language = enum {
    latex,
    bibtex,
    auto,
};

pub const Style = enum(u8) {
    text,
    comment,
    command,
    math_delimiter,
    math,
    environment,
    verbatim,
    brace,
    optional_argument,
    citation,
    label,
    reference,
    bib_entry,
    bib_field,
    bib_string,
    bib_comment,
    punctuation,
    malformed,
};

pub const TokenKind = enum(u8) {
    text,
    comment,
    command,
    math_delimiter,
    math,
    environment,
    verbatim,
    brace,
    optional_argument,
    citation,
    label,
    reference,
    bib_entry,
    bib_field,
    bib_string,
    bib_comment,
    punctuation,
    malformed,
};

pub const Token = struct {
    start: usize,
    end: usize,
    kind: TokenKind,
    style: Style,
};

pub const MathMode = enum {
    none,
    dollar,
    double_dollar,
    parenthesized,
    bracketed,
    environment,
};

pub const RawMode = enum {
    none,
    verbatim,
    comment,
};

pub const ArgumentKind = enum {
    none,
    citation,
    label,
    reference,
};

pub const EnvironmentAction = enum {
    none,
    begin,
    end,
};

const max_name = 64;
const max_raw_close = 80;
const max_bib_depth = 64;

const BibContext = enum {
    none,
    entry,
    comment_block,
};

const BibEntryKind = enum {
    unknown,
    entry,
    string,
    comment,
};

const LineCommentReturn = enum {
    normal,
    optional,
    bibtex,
};

const CommandState = struct {
    active: bool = false,
    start: usize = 0,
    name: [max_name]u8 = undefined,
    name_len: u8 = 0,
    overflow: bool = false,
    symbol: u8 = 0,
};

pub const State = struct {
    language: Language,
    offset: usize = 0,
    finished: bool = false,

    open: bool = false,
    open_start: usize = 0,
    open_kind: TokenKind = .text,
    open_style: Style = .text,

    math: MathMode = .none,
    math_environment: [max_name]u8 = undefined,
    math_environment_len: u8 = 0,
    pending_dollar: bool = false,
    pending_dollar_start: usize = 0,

    raw: RawMode = .none,
    raw_start: usize = 0,
    raw_close: [max_raw_close]u8 = undefined,
    raw_close_len: u8 = 0,
    raw_candidate_start: usize = 0,
    raw_candidate_len: u8 = 0,

    command: CommandState = .{},
    pending_argument: ArgumentKind = .none,
    active_argument: ArgumentKind = .none,
    argument_depth: usize = 0,

    pending_environment: EnvironmentAction = .none,
    environment_capture: bool = false,
    environment_action: EnvironmentAction = .none,
    environment_name: [max_name]u8 = undefined,
    environment_name_len: u8 = 0,
    environment_name_overflow: bool = false,

    optional_depth: usize = 0,
    brace_depth: usize = 0,

    line_comment: bool = false,
    line_comment_return: LineCommentReturn = .normal,

    bib_context: BibContext = .none,
    bib_entry_kind: BibEntryKind = .unknown,
    bib_depth: usize = 0,
    bib_stack: [max_bib_depth]u8 = undefined,
    bib_open: u8 = 0,
    bib_close: u8 = 0,
    bib_value_depth: usize = 0,
    bib_expect_value: bool = false,
    bib_value_atom: bool = false,
    bib_quote: bool = false,
    bib_escape: bool = false,
    bib_waiting: bool = false,
    bib_pending: bool = false,
    bib_pending_start: usize = 0,
    bib_pending_name: [max_name]u8 = undefined,
    bib_pending_name_len: u8 = 0,
    bib_pending_name_overflow: bool = false,

    utf8_expected: u8 = 0,
    utf8_seen: u8 = 0,
    utf8_first: u8 = 0,
    utf8_start: usize = 0,

    pub fn init(language: Language) State {
        return .{ .language = language };
    }

    pub fn reset(self: *State) void {
        self.* = init(self.language);
    }

    pub fn scanChunk(
        self: *State,
        allocator: std.mem.Allocator,
        input: []const u8,
        final: bool,
    ) ![]Token {
        if (self.finished) return error.AlreadyFinalized;

        var tokens: std.ArrayList(Token) = .empty;
        errdefer tokens.deinit(allocator);

        var index: usize = 0;
        while (index < input.len) : (index += 1) {
            if (self.offset == std.math.maxInt(usize)) return error.OffsetOverflow;
            const position = self.offset;
            self.offset += 1;
            const byte = input[index];

            if (self.utf8_expected != 0) {
                try self.consumeUtf8Continuation(&tokens, allocator, byte);
            } else if (byte == 0) {
                return error.EmbeddedNul;
            } else if (byte < 0x80) {
                try self.consumeAscii(&tokens, allocator, byte, position);
            } else {
                try self.startUtf8(byte, position);
            }
        }

        if (final) {
            if (self.utf8_expected != 0) return error.InvalidUtf8;
            try self.finish(&tokens, allocator);
            self.finished = true;
        }

        return tokens.toOwnedSlice(allocator);
    }

    fn startUtf8(self: *State, byte: u8, position: usize) !void {
        const expected: u8 = if (byte >= 0xc2 and byte <= 0xdf)
            2
        else if (byte >= 0xe0 and byte <= 0xef)
            3
        else if (byte >= 0xf0 and byte <= 0xf4)
            4
        else
            return error.InvalidUtf8;

        self.utf8_expected = expected;
        self.utf8_seen = 1;
        self.utf8_first = byte;
        self.utf8_start = position;
    }

    fn consumeUtf8Continuation(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
    ) !void {
        if (byte < 0x80 or byte > 0xbf) return error.InvalidUtf8;
        if (self.utf8_seen == 1) {
            const valid_second = switch (self.utf8_first) {
                0xe0 => byte >= 0xa0,
                0xed => byte <= 0x9f,
                0xf0 => byte >= 0x90,
                0xf4 => byte <= 0x8f,
                else => true,
            };
            if (!valid_second) return error.InvalidUtf8;
        }

        self.utf8_seen += 1;
        if (self.utf8_seen == self.utf8_expected) {
            const start = self.utf8_start;
            self.utf8_expected = 0;
            self.utf8_seen = 0;
            try self.consumeNonAscii(tokens, allocator, start, self.offset);
        }
    }

    fn consumeNonAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        start: usize,
        end: usize,
    ) !void {
        if (self.raw != .none) {
            try self.ensureOpen(tokens, allocator, self.raw_start, rawKind(self.raw), rawStyle(self.raw));
            return;
        }
        if (self.environment_capture) {
            self.environment_name_overflow = true;
            try self.ensureOpen(tokens, allocator, start, .environment, .environment);
            return;
        }
        if (self.bib_pending) {
            try self.finishBibPending(tokens, allocator, start);
            self.bib_waiting = false;
        }
        if (self.command.active) {
            if (self.command.name_len == 0) {
                try self.finishCommand(tokens, allocator, end);
                return;
            }
            try self.finishCommand(tokens, allocator, start);
        }
        if (self.active_argument != .none) {
            try self.ensureOpen(tokens, allocator, start, argumentKind(self.active_argument), argumentStyle(self.active_argument));
            return;
        }
        if (self.line_comment) return;
        if (self.pending_dollar) try self.flushSingleDollar(tokens, allocator, start);
        if (self.bib_context != .none) {
            try self.ensureBibOpen(tokens, allocator, start);
            return;
        }
        if (self.optional_depth != 0) {
            try self.ensureOpen(tokens, allocator, start, .optional_argument, .optional_argument);
            return;
        }
        try self.ensurePlainOpen(tokens, allocator, start);
    }

    fn consumeAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) anyerror!void {
        if (self.raw != .none) {
            try self.consumeRawAscii(tokens, allocator, byte, position);
            return;
        }
        if (self.environment_capture) {
            try self.consumeEnvironmentAscii(tokens, allocator, byte, position);
            return;
        }
        if (self.bib_pending) {
            try self.consumeBibPendingAscii(tokens, allocator, byte, position);
            return;
        }
        if (self.command.active) {
            try self.consumeCommandAscii(tokens, allocator, byte, position);
            return;
        }
        if (self.active_argument != .none) {
            try self.consumeArgumentAscii(tokens, allocator, byte, position);
            return;
        }
        if (self.line_comment) {
            try self.consumeLineCommentAscii(tokens, allocator, byte, position);
            return;
        }
        if (self.pending_dollar) {
            if (byte == '$') {
                try self.finishDoubleDollar(tokens, allocator, position);
                return;
            }
            try self.flushSingleDollar(tokens, allocator, position);
        }
        if (self.bib_context != .none) {
            try self.consumeBibAscii(tokens, allocator, byte, position);
            return;
        }
        if (self.optional_depth != 0) {
            try self.consumeOptionalAscii(tokens, allocator, byte, position);
            return;
        }
        try self.consumeNormalAscii(tokens, allocator, byte, position);
    }

    fn consumeNormalAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) !void {
        if (self.bib_waiting) {
            if (byte == '{' or byte == '(') {
                try self.startBibContext(tokens, allocator, byte, position);
                return;
            }
            if (!isSpace(byte)) self.bib_waiting = false;
        }
        const argument_modifier = self.pending_argument != .none and byte == '*';
        if (self.pending_argument != .none and
            byte != '[' and byte != '{' and !isSpace(byte) and !argument_modifier)
        {
            self.pending_argument = .none;
        }
        if (self.pending_environment != .none and byte != '{' and !isSpace(byte)) {
            self.pending_environment = .none;
        }

        switch (byte) {
            '%',
            => try self.startLineComment(tokens, allocator, position, .normal),
            '\\' => {
                try self.closeOpen(tokens, allocator, position);
                self.startCommand(position);
            },
            '$' => {
                try self.closeOpen(tokens, allocator, position);
                self.pending_dollar = true;
                self.pending_dollar_start = position;
            },
            '[' => try self.startOptional(tokens, allocator, position),
            ']' => {
                try self.closeOpen(tokens, allocator, position);
                try self.emit(tokens, allocator, position, self.offset, .malformed, .malformed);
            },
            '{' => {
                if (self.pending_environment != .none) {
                    try self.startEnvironmentCapture(tokens, allocator, position);
                } else if (self.pending_argument != .none) {
                    try self.startArgument(tokens, allocator, position);
                } else {
                    try self.emitBrace(tokens, allocator, position, true);
                }
            },
            '}' => try self.emitBrace(tokens, allocator, position, false),
            '@' => {
                if (self.language == .bibtex or self.language == .auto) {
                    try self.startBibPending(tokens, allocator, position);
                } else {
                    try self.ensurePlainOpen(tokens, allocator, position);
                }
            },
            else => try self.ensurePlainOpen(tokens, allocator, position),
        }
    }

    fn consumeOptionalAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) !void {
        switch (byte) {
            '[' => {
                try self.closeOpen(tokens, allocator, position);
                try self.emit(tokens, allocator, position, self.offset, .optional_argument, .optional_argument);
                self.optional_depth += 1;
            },
            ']' => {
                try self.closeOpen(tokens, allocator, position);
                if (self.optional_depth == 0) {
                    try self.emit(tokens, allocator, position, self.offset, .malformed, .malformed);
                } else {
                    try self.emit(tokens, allocator, position, self.offset, .optional_argument, .optional_argument);
                    self.optional_depth -= 1;
                }
            },
            '\\' => {
                try self.closeOpen(tokens, allocator, position);
                self.startCommand(position);
            },
            '%' => try self.startLineComment(tokens, allocator, position, .optional),
            else => try self.ensureOpen(tokens, allocator, position, .optional_argument, .optional_argument),
        }
    }

    fn consumeLineCommentAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) !void {
        if (byte == '\n' or byte == '\r') {
            try self.closeOpen(tokens, allocator, position);
            self.line_comment = false;
            const return_mode = self.line_comment_return;
            self.line_comment_return = .normal;
            switch (return_mode) {
                .normal => try self.consumeNormalAscii(tokens, allocator, byte, position),
                .optional => try self.consumeOptionalAscii(tokens, allocator, byte, position),
                .bibtex => try self.consumeBibAscii(tokens, allocator, byte, position),
            }
        }
    }

    fn startLineComment(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        position: usize,
        return_mode: LineCommentReturn,
    ) !void {
        try self.closeOpen(tokens, allocator, position);
        self.line_comment = true;
        self.line_comment_return = return_mode;
        const kind: TokenKind = if (return_mode == .bibtex) .bib_comment else .comment;
        const style: Style = if (return_mode == .bibtex) .bib_comment else .comment;
        try self.ensureOpen(tokens, allocator, position, kind, style);
    }

    fn startCommand(self: *State, position: usize) void {
        self.command = .{
            .active = true,
            .start = position,
        };
    }

    fn consumeCommandAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) anyerror!void {
        if (isAsciiLetter(byte)) {
            if (self.command.name_len < max_name) {
                self.command.name[self.command.name_len] = byte;
                self.command.name_len += 1;
            } else {
                self.command.overflow = true;
            }
            return;
        }

        if (self.command.name_len == 0) {
            self.command.symbol = byte;
            try self.finishCommand(tokens, allocator, self.offset);
            return;
        }

        try self.finishCommand(tokens, allocator, position);
        try self.consumeAscii(tokens, allocator, byte, position);
    }

    fn finishCommand(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        end: usize,
    ) !void {
        const command = self.command;
        self.command = .{};

        if (command.name_len == 0) {
            switch (command.symbol) {
                '(' => {
                    try self.emitMathCommand(tokens, allocator, command.start, end, .parenthesized);
                },
                ')' => {
                    try self.emitMathCommand(tokens, allocator, command.start, end, .parenthesized);
                },
                '[' => {
                    try self.emitMathCommand(tokens, allocator, command.start, end, .bracketed);
                },
                ']' => {
                    try self.emitMathCommand(tokens, allocator, command.start, end, .bracketed);
                },
                '%' => try self.emit(tokens, allocator, command.start, end, .command, .command),
                else => try self.emit(tokens, allocator, command.start, end, .command, .command),
            }
            return;
        }

        try self.emit(tokens, allocator, command.start, end, .command, .command);
        if (command.overflow) return;
        const name = command.name[0..command.name_len];
        if (std.mem.eql(u8, name, "begin")) {
            self.pending_environment = .begin;
        } else if (std.mem.eql(u8, name, "end")) {
            self.pending_environment = .end;
        } else if (isCitationCommand(name)) {
            self.pending_argument = .citation;
        } else if (isLabelCommand(name)) {
            self.pending_argument = .label;
        } else if (isReferenceCommand(name)) {
            self.pending_argument = .reference;
        }
    }

    fn emitMathCommand(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        start: usize,
        end: usize,
        mode: MathMode,
    ) !void {
        try self.closeOpen(tokens, allocator, start);
        try self.emit(tokens, allocator, start, end, .math_delimiter, .math_delimiter);
        if (self.math == .none) {
            self.math = mode;
        } else if (self.math == mode) {
            self.math = .none;
        }
    }

    fn startOptional(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        position: usize,
    ) !void {
        try self.closeOpen(tokens, allocator, position);
        try self.emit(tokens, allocator, position, self.offset, .optional_argument, .optional_argument);
        self.optional_depth = 1;
    }

    fn startArgument(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        position: usize,
    ) !void {
        const argument = self.pending_argument;
        self.pending_argument = .none;
        try self.emitBrace(tokens, allocator, position, true);
        self.active_argument = argument;
        self.argument_depth = 1;
    }

    fn consumeArgumentAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) !void {
        switch (byte) {
            '{' => {
                try self.closeOpen(tokens, allocator, position);
                try self.emitBrace(tokens, allocator, position, true);
                self.argument_depth += 1;
            },
            '}' => {
                try self.closeOpen(tokens, allocator, position);
                try self.emitBrace(tokens, allocator, position, false);
                if (self.argument_depth != 0) self.argument_depth -= 1;
                if (self.argument_depth == 0) self.active_argument = .none;
            },
            else => try self.ensureOpen(
                tokens,
                allocator,
                position,
                argumentKind(self.active_argument),
                argumentStyle(self.active_argument),
            ),
        }
    }

    fn startEnvironmentCapture(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        position: usize,
    ) !void {
        const action = self.pending_environment;
        self.pending_environment = .none;
        try self.emitBrace(tokens, allocator, position, true);
        self.environment_capture = true;
        self.environment_action = action;
        self.environment_name_len = 0;
        self.environment_name_overflow = false;
    }

    fn consumeEnvironmentAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) !void {
        if (byte == '}') {
            try self.closeOpen(tokens, allocator, position);
            try self.emitBrace(tokens, allocator, position, false);
            self.environment_capture = false;
            try self.finishEnvironment();
            return;
        }

        try self.ensureOpen(tokens, allocator, position, .environment, .environment);
        if (isEnvironmentChar(byte)) {
            if (self.environment_name_len < max_name) {
                self.environment_name[self.environment_name_len] = byte;
                self.environment_name_len += 1;
            } else {
                self.environment_name_overflow = true;
            }
        } else {
            self.environment_name_overflow = true;
        }
    }

    fn finishEnvironment(self: *State) !void {
        const name = self.environment_name[0..self.environment_name_len];
        const valid = !self.environment_name_overflow and name.len != 0;
        const action = self.environment_action;
        self.environment_action = .none;
        if (!valid) return;

        switch (action) {
            .begin => {
                if (rawModeFor(name)) |raw| {
                    self.setRaw(raw, name);
                } else if (isMathEnvironment(name)) {
                    self.math = .environment;
                    self.math_environment_len = @intCast(@min(name.len, max_name));
                    std.mem.copyForwards(u8, self.math_environment[0..self.math_environment_len], name[0..self.math_environment_len]);
                }
            },
            .end => {
                if (self.math == .environment and
                    std.mem.eql(u8, self.math_environment[0..self.math_environment_len], name))
                {
                    self.math = .none;
                    self.math_environment_len = 0;
                }
            },
            .none => {},
        }
    }

    fn setRaw(self: *State, mode: RawMode, name: []const u8) void {
        const prefix = "\\end{";
        if (name.len > max_raw_close - prefix.len - 1) return;
        self.raw = mode;
        self.raw_start = self.offset;
        self.raw_candidate_len = 0;
        std.mem.copyForwards(u8, self.raw_close[0..prefix.len], prefix);
        std.mem.copyForwards(u8, self.raw_close[prefix.len .. prefix.len + name.len], name);
        self.raw_close[prefix.len + name.len] = '}';
        self.raw_close_len = @intCast(prefix.len + name.len + 1);
    }

    fn consumeRawAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) !void {
        try self.ensureOpen(tokens, allocator, self.raw_start, rawKind(self.raw), rawStyle(self.raw));
        if (self.raw_candidate_len == 0) {
            if (byte == '\\') {
                self.raw_candidate_start = position;
                self.raw_candidate_len = 1;
            }
            return;
        }

        const candidate_index: usize = self.raw_candidate_len;
        if (candidate_index < self.raw_close_len and byte == self.raw_close[candidate_index]) {
            self.raw_candidate_len += 1;
            if (self.raw_candidate_len == self.raw_close_len) {
                const marker_start = self.raw_candidate_start;
                try self.closeOpen(tokens, allocator, marker_start);
                try self.emit(tokens, allocator, marker_start, self.offset, .environment, .environment);
                self.raw = .none;
                self.raw_candidate_len = 0;
            }
            return;
        }

        self.raw_candidate_len = 0;
        if (byte == '\\') {
            self.raw_candidate_start = position;
            self.raw_candidate_len = 1;
        }
    }

    fn startBibPending(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        position: usize,
    ) !void {
        try self.closeOpen(tokens, allocator, position);
        self.bib_pending = true;
        self.bib_pending_start = position;
        self.bib_pending_name_len = 0;
        self.bib_pending_name_overflow = false;
    }

    fn consumeBibPendingAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) !void {
        if (isAsciiLetter(byte)) {
            if (self.bib_pending_name_len < max_name) {
                self.bib_pending_name[self.bib_pending_name_len] = byte;
                self.bib_pending_name_len += 1;
            } else {
                self.bib_pending_name_overflow = true;
            }
            return;
        }

        try self.finishBibPending(tokens, allocator, position);
        if (self.bib_waiting) {
            if (byte == '{' or byte == '(') {
                try self.startBibContext(tokens, allocator, byte, position);
            } else if (isSpace(byte)) {
                try self.ensurePlainOpen(tokens, allocator, position);
            } else {
                self.bib_waiting = false;
                try self.consumeNormalAscii(tokens, allocator, byte, position);
            }
        } else {
            try self.consumeNormalAscii(tokens, allocator, byte, position);
        }
    }

    fn finishBibPending(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        end: usize,
    ) !void {
        const pending_start = self.bib_pending_start;
        const name = self.bib_pending_name[0..self.bib_pending_name_len];
        const kind = if (self.bib_pending_name_overflow) .unknown else bibEntryKind(name);
        self.bib_pending = false;
        self.bib_pending_name_len = 0;
        if (kind == .unknown) {
            try self.emit(tokens, allocator, pending_start, end, .malformed, .malformed);
            self.bib_entry_kind = .unknown;
            self.bib_waiting = false;
            return;
        }
        try self.emit(tokens, allocator, pending_start, end, .bib_entry, .bib_entry);
        self.bib_entry_kind = kind;
        self.bib_waiting = true;
    }

    fn startBibContext(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        opening: u8,
        position: usize,
    ) !void {
        try self.closeOpen(tokens, allocator, position);
        try self.emit(tokens, allocator, position, self.offset, .brace, .brace);
        self.bib_waiting = false;
        self.bib_context = if (self.bib_entry_kind == .comment) .comment_block else .entry;
        self.bib_depth = 1;
        self.bib_open = opening;
        self.bib_close = if (opening == '(') ')' else '}';
        self.bib_value_depth = 0;
        self.bib_expect_value = false;
    }

    fn consumeBibAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) !void {
        if (self.bib_context == .comment_block) {
            try self.consumeBibCommentAscii(tokens, allocator, byte, position);
            return;
        }
        if (self.bib_quote) {
            if (byte == '\\' and !self.bib_escape) {
                self.bib_escape = true;
                try self.ensureOpen(tokens, allocator, position, .bib_string, .bib_string);
            } else if (byte == '"' and !self.bib_escape) {
                try self.closeOpen(tokens, allocator, position);
                try self.emit(tokens, allocator, position, self.offset, .punctuation, .punctuation);
                self.bib_quote = false;
                self.bib_expect_value = false;
            } else {
                self.bib_escape = false;
                try self.ensureOpen(tokens, allocator, position, .bib_string, .bib_string);
            }
            return;
        }

        if (byte == '%') {
            try self.startLineComment(tokens, allocator, position, .bibtex);
            return;
        }
        if (self.bib_value_depth > 0) {
            if (byte == '}') {
                try self.closeOpen(tokens, allocator, position);
                self.bib_value_depth -= 1;
                if (self.bib_value_depth == 0) {
                    try self.emit(tokens, allocator, position, self.offset, .brace, .brace);
                    self.bib_expect_value = false;
                } else {
                    try self.emit(tokens, allocator, position, self.offset, .bib_string, .bib_string);
                }
                return;
            }
            if (byte == '{') {
                try self.closeOpen(tokens, allocator, position);
                try self.emit(tokens, allocator, position, self.offset, .bib_string, .bib_string);
                self.bib_value_depth += 1;
                return;
            }
            try self.ensureOpen(tokens, allocator, position, .bib_string, .bib_string);
            return;
        }
        if (byte == '{') {
            try self.closeOpen(tokens, allocator, position);
            try self.emit(tokens, allocator, position, self.offset, .brace, .brace);
            if (self.bib_expect_value) {
                self.bib_value_depth = 1;
            } else if (self.bib_open == '{') {
                self.bib_depth += 1;
            }
            return;
        }
        if (byte == self.bib_close) {
            try self.closeOpen(tokens, allocator, position);
            try self.emit(tokens, allocator, position, self.offset, .brace, .brace);
            if (self.bib_depth > 1) {
                self.bib_depth -= 1;
            } else {
                self.bib_context = .none;
                self.bib_entry_kind = .unknown;
                self.bib_value_depth = 0;
                self.bib_expect_value = false;
            }
            return;
        }
        if (byte == self.bib_open and self.bib_open != '{') {
            try self.closeOpen(tokens, allocator, position);
            try self.emit(tokens, allocator, position, self.offset, .brace, .brace);
            self.bib_depth += 1;
            return;
        }
        if (byte == '"') {
            try self.closeOpen(tokens, allocator, position);
            try self.emit(tokens, allocator, position, self.offset, .punctuation, .punctuation);
            self.bib_quote = true;
            self.bib_escape = false;
            return;
        }
        if (byte == '=') {
            try self.closeOpen(tokens, allocator, position);
            try self.emit(tokens, allocator, position, self.offset, .punctuation, .punctuation);
            self.bib_expect_value = true;
            return;
        }
        if (byte == ',') {
            try self.closeOpen(tokens, allocator, position);
            try self.emit(tokens, allocator, position, self.offset, .punctuation, .punctuation);
            self.bib_expect_value = false;
            self.bib_value_depth = 0;
            return;
        }
        if (byte == '#' or byte == '+' or byte == '-') {
            try self.closeOpen(tokens, allocator, position);
            try self.emit(tokens, allocator, position, self.offset, .punctuation, .punctuation);
            return;
        }
        if (isBibIdentifier(byte)) {
            if (self.bib_expect_value or self.bib_value_depth != 0) {
                try self.ensureOpen(tokens, allocator, position, .bib_string, .bib_string);
            } else {
                try self.ensureOpen(tokens, allocator, position, .bib_field, .bib_field);
            }
            return;
        }
        try self.ensureBibOpen(tokens, allocator, position);
    }

    fn consumeBibCommentAscii(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        byte: u8,
        position: usize,
    ) !void {
        if (byte == self.bib_close) {
            try self.closeOpen(tokens, allocator, position);
            if (self.bib_depth > 1) {
                try self.emit(tokens, allocator, position, self.offset, .bib_comment, .bib_comment);
                self.bib_depth -= 1;
            } else {
                try self.emit(tokens, allocator, position, self.offset, .brace, .brace);
                self.bib_context = .none;
                self.bib_entry_kind = .unknown;
            }
            return;
        }
        if (byte == self.bib_open) {
            try self.closeOpen(tokens, allocator, position);
            try self.emit(tokens, allocator, position, self.offset, .bib_comment, .bib_comment);
            self.bib_depth += 1;
            return;
        }
        try self.ensureOpen(tokens, allocator, position, .bib_comment, .bib_comment);
    }

    fn ensureBibOpen(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        position: usize,
    ) !void {
        if (self.bib_context == .comment_block) {
            try self.ensureOpen(tokens, allocator, position, .bib_comment, .bib_comment);
        } else if (self.bib_expect_value or self.bib_value_depth != 0) {
            try self.ensureOpen(tokens, allocator, position, .bib_string, .bib_string);
        } else {
            try self.ensureOpen(tokens, allocator, position, .text, .text);
        }
    }

    fn ensurePlainOpen(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        position: usize,
    ) !void {
        if (self.optional_depth != 0) {
            try self.ensureOpen(tokens, allocator, position, .optional_argument, .optional_argument);
        } else if (self.math != .none) {
            try self.ensureOpen(tokens, allocator, position, .math, .math);
        } else {
            try self.ensureOpen(tokens, allocator, position, .text, .text);
        }
    }

    fn emitBrace(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        position: usize,
        opening: bool,
    ) !void {
        try self.closeOpen(tokens, allocator, position);
        if (opening) {
            self.brace_depth += 1;
        } else if (self.brace_depth == 0) {
            try self.emit(tokens, allocator, position, self.offset, .malformed, .malformed);
            return;
        } else {
            self.brace_depth -= 1;
        }
        try self.emit(tokens, allocator, position, self.offset, .brace, .brace);
    }

    fn flushSingleDollar(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        end: usize,
    ) !void {
        const start = self.pending_dollar_start;
        self.pending_dollar = false;
        if (self.math == .none) {
            try self.closeOpen(tokens, allocator, start);
            try self.emit(tokens, allocator, start, end, .math_delimiter, .math_delimiter);
            self.math = .dollar;
        } else if (self.math == .dollar) {
            try self.closeOpen(tokens, allocator, start);
            try self.emit(tokens, allocator, start, end, .math_delimiter, .math_delimiter);
            self.math = .none;
        } else {
            try self.ensureOpen(tokens, allocator, start, .math, .math);
        }
    }

    fn finishDoubleDollar(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        position: usize,
    ) !void {
        const start = self.pending_dollar_start;
        self.pending_dollar = false;
        if (self.math == .none) {
            try self.closeOpen(tokens, allocator, start);
            try self.emit(tokens, allocator, start, self.offset, .math_delimiter, .math_delimiter);
            self.math = .double_dollar;
        } else if (self.math == .double_dollar) {
            try self.closeOpen(tokens, allocator, start);
            try self.emit(tokens, allocator, start, self.offset, .math_delimiter, .math_delimiter);
            self.math = .none;
        } else if (self.math == .dollar) {
            try self.closeOpen(tokens, allocator, start);
            try self.emit(tokens, allocator, start, start + 1, .math_delimiter, .math_delimiter);
            self.math = .none;
            self.pending_dollar = true;
            self.pending_dollar_start = position;
        } else {
            try self.ensureOpen(tokens, allocator, start, .math, .math);
        }
    }

    fn finish(self: *State, tokens: *std.ArrayList(Token), allocator: std.mem.Allocator) !void {
        if (self.pending_dollar) try self.flushSingleDollar(tokens, allocator, self.offset);
        if (self.command.active) try self.finishCommand(tokens, allocator, self.offset);
        if (self.bib_pending) try self.finishBibPending(tokens, allocator, self.offset);
        if (self.environment_capture) {
            self.markOpenMalformed();
            try self.closeOpen(tokens, allocator, self.offset);
            self.environment_capture = false;
        }
        if (self.active_argument != .none) {
            self.markOpenMalformed();
            try self.closeOpen(tokens, allocator, self.offset);
            self.active_argument = .none;
            self.argument_depth = 0;
        }
        if (self.bib_quote) {
            self.markOpenMalformed();
            try self.closeOpen(tokens, allocator, self.offset);
            self.bib_quote = false;
        }
        if (self.raw != .none) {
            self.markOpenMalformed();
            try self.closeOpen(tokens, allocator, self.offset);
            self.raw = .none;
            self.raw_candidate_len = 0;
        }
        if (self.line_comment) {
            try self.closeOpen(tokens, allocator, self.offset);
            self.line_comment = false;
        }
        if (self.optional_depth != 0 and self.open and self.open_style == .optional_argument) self.markOpenMalformed();
        if (self.math != .none and self.open and self.open_style == .math) self.markOpenMalformed();
        if (self.brace_depth != 0 and self.open and self.open_style == .text) self.markOpenMalformed();
        if (self.bib_context != .none and self.open) self.markOpenMalformed();
        try self.closeOpen(tokens, allocator, self.offset);
    }

    fn markOpenMalformed(self: *State) void {
        if (self.open) {
            self.open_kind = .malformed;
            self.open_style = .malformed;
        }
    }

    fn ensureOpen(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        position: usize,
        kind: TokenKind,
        style: Style,
    ) !void {
        if (self.open and self.open_kind == kind and self.open_style == style) return;
        try self.closeOpen(tokens, allocator, position);
        self.open = true;
        self.open_start = position;
        self.open_kind = kind;
        self.open_style = style;
    }

    fn closeOpen(
        self: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        end: usize,
    ) !void {
        if (!self.open) return;
        if (end > self.open_start) {
            try self.emit(tokens, allocator, self.open_start, end, self.open_kind, self.open_style);
        }
        self.open = false;
    }

    fn emit(
        _: *State,
        tokens: *std.ArrayList(Token),
        allocator: std.mem.Allocator,
        start: usize,
        end: usize,
        kind: TokenKind,
        style: Style,
    ) !void {
        if (end <= start) return;
        try tokens.append(allocator, .{
            .start = start,
            .end = end,
            .kind = kind,
            .style = style,
        });
    }
};

pub fn lex(allocator: std.mem.Allocator, language: Language, input: []const u8) ![]Token {
    var state = State.init(language);
    return state.scanChunk(allocator, input, true);
}

fn argumentKind(argument: ArgumentKind) TokenKind {
    return switch (argument) {
        .citation => .citation,
        .label => .label,
        .reference => .reference,
        .none => .malformed,
    };
}

fn argumentStyle(argument: ArgumentKind) Style {
    return switch (argument) {
        .citation => .citation,
        .label => .label,
        .reference => .reference,
        .none => .malformed,
    };
}

fn rawKind(raw: RawMode) TokenKind {
    return switch (raw) {
        .verbatim => .verbatim,
        .comment => .comment,
        .none => .text,
    };
}

fn rawStyle(raw: RawMode) Style {
    return switch (raw) {
        .verbatim => .verbatim,
        .comment => .comment,
        .none => .text,
    };
}

fn isAsciiLetter(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z');
}

fn isSpace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r' or byte == 0x0b or byte == 0x0c;
}

fn isEnvironmentChar(byte: u8) bool {
    return isAsciiLetter(byte) or (byte >= '0' and byte <= '9') or byte == '*' or byte == '-' or byte == '_';
}

fn isBibIdentifier(byte: u8) bool {
    return isAsciiLetter(byte) or (byte >= '0' and byte <= '9') or byte == '_' or byte == '-' or byte == ':' or byte == '.';
}

fn isCitationCommand(name: []const u8) bool {
    return std.mem.eql(u8, name, "cite") or
        std.mem.eql(u8, name, "citep") or
        std.mem.eql(u8, name, "citet") or
        std.mem.eql(u8, name, "parencite") or
        std.mem.eql(u8, name, "textcite") or
        std.mem.eql(u8, name, "autocite") or
        std.mem.eql(u8, name, "footcite") or
        std.mem.eql(u8, name, "citeauthor") or
        std.mem.eql(u8, name, "citetitle");
}

fn isLabelCommand(name: []const u8) bool {
    return std.mem.eql(u8, name, "label");
}

fn isReferenceCommand(name: []const u8) bool {
    return std.mem.eql(u8, name, "ref") or
        std.mem.eql(u8, name, "pageref") or
        std.mem.eql(u8, name, "autoref") or
        std.mem.eql(u8, name, "cref") or
        std.mem.eql(u8, name, "Cref") or
        std.mem.eql(u8, name, "eqref");
}

fn isMathEnvironment(name: []const u8) bool {
    return std.mem.eql(u8, name, "math") or
        std.mem.eql(u8, name, "displaymath") or
        std.mem.eql(u8, name, "equation") or
        std.mem.eql(u8, name, "equation*") or
        std.mem.eql(u8, name, "align") or
        std.mem.eql(u8, name, "align*") or
        std.mem.eql(u8, name, "gather") or
        std.mem.eql(u8, name, "gather*") or
        std.mem.eql(u8, name, "multline") or
        std.mem.eql(u8, name, "multline*");
}

fn rawModeFor(name: []const u8) ?RawMode {
    if (std.mem.eql(u8, name, "comment")) return .comment;
    if (std.mem.eql(u8, name, "verbatim") or
        std.mem.eql(u8, name, "verbatim*") or
        std.mem.eql(u8, name, "Verbatim") or
        std.mem.eql(u8, name, "lstlisting") or
        std.mem.eql(u8, name, "minted")) return .verbatim;
    return null;
}

fn bibEntryKind(name: []const u8) BibEntryKind {
    if (std.mem.eql(u8, name, "comment")) return .comment;
    if (std.mem.eql(u8, name, "string")) return .string;
    if (name.len != 0) return .entry;
    return .unknown;
}
