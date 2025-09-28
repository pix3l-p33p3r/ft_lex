const std = @import("std");
const testing = std.testing;
const regex = @import("regex/parser.zig");
const NFA = @import("automata/nfa.zig").NFA;
const EPSILON = @import("automata/nfa.zig").EPSILON;

test "simple character" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var nfa = try regex.parseRegex(allocator, "a");
    defer nfa.deinit();

    try testing.expectEqual(@as(usize, 2), nfa.states.items.len);
    try testing.expect(!nfa.states.items[0].is_accepting);
    try testing.expect(nfa.states.items[1].is_accepting);
}

test "concatenation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var nfa = try regex.parseRegex(allocator, "ab");
    defer nfa.deinit();

    try testing.expectEqual(@as(usize, 3), nfa.states.items.len);
    try testing.expect(!nfa.states.items[0].is_accepting);
    try testing.expect(!nfa.states.items[1].is_accepting);
    try testing.expect(nfa.states.items[2].is_accepting);
}

test "alternation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var nfa = try regex.parseRegex(allocator, "a|b");
    defer nfa.deinit();

    try testing.expectEqual(@as(usize, 5), nfa.states.items.len);
    try testing.expect(!nfa.states.items[0].is_accepting);
    try testing.expect(nfa.states.items[2].is_accepting);
    try testing.expect(nfa.states.items[4].is_accepting);
}

test "kleene star" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var nfa = try regex.parseRegex(allocator, "a*");
    defer nfa.deinit();

    try testing.expectEqual(@as(usize, 3), nfa.states.items.len);
    try testing.expect(!nfa.states.items[0].is_accepting);
    try testing.expect(nfa.states.items[2].is_accepting);
}

test "complex regex" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var nfa = try regex.parseRegex(allocator, "(a|b)*c");
    defer nfa.deinit();

    // Verify the structure without checking exact state count
    // as it may vary based on implementation
    try testing.expect(nfa.states.items.len > 5);
    try testing.expect(nfa.states.items[nfa.states.items.len - 1].is_accepting);
}
