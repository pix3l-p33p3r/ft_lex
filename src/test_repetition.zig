const std = @import("std");
const testing = std.testing;
const repetition = @import("regex/repetition.zig");

test "parse exact repetition" {
    var parser = repetition.RepetitionParser.init("{3}");
    var range = try parser.parse();
    try testing.expectEqual(@as(usize, 3), range.min);
    try testing.expectEqual(@as(?usize, 3), range.max);
}

test "parse minimum repetition" {
    var parser = repetition.RepetitionParser.init("{3,}");
    var range = try parser.parse();
    try testing.expectEqual(@as(usize, 3), range.min);
    try testing.expectEqual(@as(?usize, null), range.max);
}

test "parse range repetition" {
    var parser = repetition.RepetitionParser.init("{3,5}");
    var range = try parser.parse();
    try testing.expectEqual(@as(usize, 3), range.min);
    try testing.expectEqual(@as(?usize, 5), range.max);
}

test "parse invalid range" {
    var parser = repetition.RepetitionParser.init("{5,3}");
    try testing.expectError(error.InvalidRange, parser.parse());
}

test "parse unterminated repetition" {
    var parser = repetition.RepetitionParser.init("{3");
    try testing.expectError(error.UnterminatedRepetition, parser.parse());
}
