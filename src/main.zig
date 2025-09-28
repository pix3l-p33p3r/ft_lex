const std = @import("std");
const parser = @import("parser/parser.zig");
const codegen = @import("codegen/codegen.zig");
const NFA = @import("automata/nfa.zig").NFA;
const DFA = @import("automata/dfa.zig").DFA;

fn buildDFA(allocator: std.mem.Allocator, rules: []const parser.Rule) !DFA {
    var nfa = NFA.init(allocator);
    defer nfa.deinit();

    // Build NFA for each rule
    for (rules) |rule| {
        var rule_nfa = try NFA.fromPattern(allocator, rule.pattern);
        defer rule_nfa.deinit();
        try nfa.concat(&rule_nfa);
    }

    // Convert NFA to DFA and minimize
    var dfa = try DFA.fromNFA(allocator, &nfa);
    try dfa.minimize();
    return dfa;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: ft_lex input.l\n", .{});
        std.process.exit(1);
    }

    // Parse input file
    const input_file = args[1];
    var lexfile = try parser.parseLexFile(allocator, input_file);
    defer lexfile.deinit();

    // Build DFA from rules
    var dfa = try buildDFA(allocator, lexfile.rules.items);
    defer dfa.deinit();

    // Generate C code
    try codegen.generateCode(allocator, lexfile, &dfa, "lex.yy.c");
}
