const std = @import("std");
const testing = std.testing;
const codegen = @import("codegen/codegen.zig");
const parser = @import("parser/parser.zig");
const DFA = @import("automata/dfa.zig").DFA;

test "generate simple lexer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a simple DFA for recognizing numbers
    var dfa = DFA.init(allocator);
    defer dfa.deinit();

    const s0 = try dfa.addState();
    const s1 = try dfa.addState();
    dfa.start = s0;
    dfa.states.items[s1].is_accepting = true;

    var i: u8 = '0';
    while (i <= '9') : (i += 1) {
        try dfa.states.items[s0].transitions.put(i, s1);
        try dfa.states.items[s1].transitions.put(i, s1);
    }

    // Create a simple lexfile
    var lexfile = parser.LexFile.init(allocator);
    defer lexfile.deinit();

    // Generate the lexer
    try codegen.generateCode(allocator, lexfile, &dfa, "test_lexer.c");

    // Verify the file was created
    const file = try std.fs.cwd().openFile("test_lexer.c", .{});
    defer file.close();
}

test "generate lexer with actions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a DFA for recognizing numbers and operators
    var dfa = DFA.init(allocator);
    defer dfa.deinit();

    const s0 = try dfa.addState(); // start
    const s1 = try dfa.addState(); // number
    const s2 = try dfa.addState(); // operator
    dfa.start = s0;
    dfa.states.items[s1].is_accepting = true;
    dfa.states.items[s2].is_accepting = true;

    // Add transitions for numbers
    var i: u8 = '0';
    while (i <= '9') : (i += 1) {
        try dfa.states.items[s0].transitions.put(i, s1);
        try dfa.states.items[s1].transitions.put(i, s1);
    }

    // Add transitions for operators
    try dfa.states.items[s0].transitions.put('+', s2);
    try dfa.states.items[s0].transitions.put('-', s2);
    try dfa.states.items[s0].transitions.put('*', s2);
    try dfa.states.items[s0].transitions.put('/', s2);

    // Create a lexfile with actions
    var lexfile = parser.LexFile.init(allocator);
    defer lexfile.deinit();

    // Generate the lexer
    try codegen.generateCode(allocator, lexfile, &dfa, "test_lexer_actions.c");

    // Verify the file was created
    const file = try std.fs.cwd().openFile("test_lexer_actions.c", .{});
    defer file.close();
}
