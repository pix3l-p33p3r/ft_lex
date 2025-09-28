const std = @import("std");
const testing = std.testing;
const minimize = @import("automata/minimize.zig");
const DFA = @import("automata/dfa.zig").DFA;

test "minimize simple DFA" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a simple DFA for (a|b)*a
    var dfa = DFA.init(allocator);
    defer dfa.deinit();

    const s0 = try dfa.addState(); // start
    const s1 = try dfa.addState(); // seen 'a'
    dfa.start = s0;
    dfa.states.items[s1].is_accepting = true;

    try dfa.states.items[s0].transitions.put('a', s1);
    try dfa.states.items[s0].transitions.put('b', s0);
    try dfa.states.items[s1].transitions.put('a', s1);
    try dfa.states.items[s1].transitions.put('b', s0);

    var min_dfa = try minimize.MinimizedDFA.init(allocator, &dfa);
    defer min_dfa.deinit();

    // The minimized DFA should have the same number of states
    // as this DFA is already minimal
    try testing.expectEqual(@as(usize, 2), min_dfa.dfa.states.items.len);
}

test "minimize reducible DFA" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a DFA for 'a' with redundant states
    var dfa = DFA.init(allocator);
    defer dfa.deinit();

    const s0 = try dfa.addState(); // start
    const s1 = try dfa.addState(); // intermediate
    const s2 = try dfa.addState(); // accepting
    dfa.start = s0;
    dfa.states.items[s2].is_accepting = true;

    try dfa.states.items[s0].transitions.put('a', s1);
    try dfa.states.items[s1].transitions.put('a', s2);

    var min_dfa = try minimize.MinimizedDFA.init(allocator, &dfa);
    defer min_dfa.deinit();

    // The minimized DFA should have only 2 states
    try testing.expectEqual(@as(usize, 2), min_dfa.dfa.states.items.len);
}
