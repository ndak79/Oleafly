// Shared inputs only: the child never imports the serializer.
pub const arguments: []const []const u8 = &.{
    "",
    "plain",
    "two words\tand tab",
    "\"",
    "a\"b\"c",
    "\\",
    "\\\\",
    "trailing space \\",
    "one\\\"two\\\\\"three",
    "Ti\u{1ebf}ng Vi\u{1ec7}t / \u{4e2d}\u{6587} / \u{1f642}",
    "e\u{301} != \u{e9}",
    "& | < > ^ %PATH% $(literal);",
    "x" ** 4096,
};
