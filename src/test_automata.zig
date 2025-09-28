const std = @import("std");
const testing = std.testing;
const charclass = @import("regex/charclass.zig");
const regex = @import("regex/parser.zig");
const dfa = @import("automata/dfa.zig");

test "character class basic" {
    var parser = charclass.CharClassParser.init("abc");
    var charset = try parser.parse();

    try testing.expect(charset.contains('a'));
    try testing.expect(charset.contains('b'));
    try testing.expect(charset.contains('c'));
    try testing.expect(!charset.contains('d'));
}

test "character class range" {
    var parser = charclass.CharClassParser.init("a-z");
    var charset = try parser.parse();

    try testing.expect(charset.contains('a'));
    try testing.expect(charset.contains('m'));
    try testing.expect(charset.contains('z'));
    try testing.expect(!charset.contains('A'));
}

test "character class negation" {
    var parser = charclass.CharClassParser.init("^abc");
    var charset = try parser.parse();

    try testing.expect(!charset.contains('a'));
    try testing.expect(!charset.contains('b'));
    try testing.expect(!charset.contains('c'));
    try testing.expect(charset.contains('d'));
}

test "character class POSIX" {
    var parser = charclass.CharClassParser.init("[:digit:]");
    var charset = try parser.parse();

    try testing.expect(charset.contains('0'));
    try testing.expect(charset.contains('9'));
    try testing.expect(!charset.contains('a'));
}

test "NFA to DFA simple" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var nfa = try regex.parseRegex(allocator, "a");
    defer nfa.deinit();

    var dfa_machine = try dfa.DFA.fromNFA(allocator, &nfa);
    defer dfa_machine.deinit();

    try testing.expect(dfa_machine.states.items.len <= 2);
    try testing.expect(!dfa_machine.states.items[0].is_accepting);
    try testing.expect(dfa_machine.states.items[1].is_accepting);
}

test "NFA to DFA with alternation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var nfa = try regex.parseRegex(allocator, "a|b");
    defer nfa.deinit();

    var dfa_machine = try dfa.DFA.fromNFA(allocator, &nfa);
    defer dfa_machine.deinit();

    // DFA should have 3 states: start, accept-a, accept-b
    try testing.expect(dfa_machine.states.items.len <= 3);
}
