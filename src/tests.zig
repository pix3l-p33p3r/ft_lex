const std = @import("std");
const diag = @import("diag.zig");
const lexfile = @import("lexfile.zig");
const regex = @import("regex.zig");
const nfa_mod = @import("nfa.zig");
const dfa_mod = @import("dfa.zig");

comptime {
    _ = @import("lexfile.zig");
    _ = @import("regex.zig");
}

fn compileDfa(alloc: std.mem.Allocator, src: []const u8) !dfa_mod.Dfa {
    var d = diag.Diag{};
    const spec = try lexfile.parse(alloc, &d, "t.l", src);
    const nfa = try nfa_mod.build(alloc, &d, &spec);
    return dfa_mod.build(alloc, &d, &nfa, spec.tables.states);
}

test "longest match prefers longer token" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const dfa = try compileDfa(arena.allocator(),
        \\%%
        \\if      { return 1; }
        \\[a-z]+  { return 2; }
        \\
    );
    const m1 = dfa_mod.matchLongest(&dfa, "if", 0, true).?;
    try std.testing.expectEqual(@as(i32, 0), m1.rule);
    try std.testing.expectEqual(@as(usize, 2), m1.len);
    const m2 = dfa_mod.matchLongest(&dfa, "iffy", 0, true).?;
    try std.testing.expectEqual(@as(i32, 1), m2.rule);
    try std.testing.expectEqual(@as(usize, 4), m2.len);
}

test "digits and operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const dfa = try compileDfa(arena.allocator(),
        \\%%
        \\[0-9]+ { return 1; }
        \\"+"    { return 2; }
        \\
    );
    const n = dfa_mod.matchLongest(&dfa, "42", 0, true).?;
    try std.testing.expectEqual(@as(i32, 0), n.rule);
    try std.testing.expectEqual(@as(usize, 2), n.len);
    const op = dfa_mod.matchLongest(&dfa, "+", 0, true).?;
    try std.testing.expectEqual(@as(i32, 1), op.rule);
}

test "bad regex is a user error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diag{};
    try std.testing.expectError(
        error.CompileFail,
        regex.parseEre(arena.allocator(), &d, &.{}, "(abc", 3),
    );
    try std.testing.expectEqualStrings("unbalanced parenthesis", d.msg());
}
