const std = @import("std");
const dfa_mod = @import("dfa.zig");

/// Equivalence-class + unique-row packing of a DFA transition table.
pub const Packed = struct {
    ec: [256]u8,
    nclass: u16,
    row: []u16,
    nrows: u16,
    nxt: []i16, // row-major: nxt[row * nclass + class]

    pub fn next(self: Packed, state: u32, c: u8) i32 {
        const cls = self.ec[c];
        const r = self.row[state];
        return self.nxt[@as(usize, r) * self.nclass + cls];
    }
};

fn sameColumn(dfa: *const dfa_mod.Dfa, a: u16, b: u16) bool {
    for (dfa.states) |st| {
        if (st.trans[a] != st.trans[b]) return false;
    }
    return true;
}

pub fn pack(alloc: std.mem.Allocator, dfa: *const dfa_mod.Dfa) !Packed {
    var ec: [256]u8 = undefined;
    var rep: [256]u16 = undefined;
    var nclass: u16 = 0;

    var a: u16 = 0;
    while (a < 256) : (a += 1) {
        var found: ?u16 = null;
        var k: u16 = 0;
        while (k < nclass) : (k += 1) {
            if (sameColumn(dfa, a, rep[k])) {
                found = k;
                break;
            }
        }
        if (found) |cls| {
            ec[a] = @truncate(cls);
        } else {
            rep[nclass] = a;
            ec[a] = @truncate(nclass);
            nclass += 1;
        }
    }

    const nstates = dfa.states.len;
    var row = try alloc.alloc(u16, nstates);
    var rows = std.ArrayList([]i16).init(alloc);

    var s: usize = 0;
    while (s < nstates) : (s += 1) {
        const vec = try alloc.alloc(i16, nclass);
        var cls: u16 = 0;
        while (cls < nclass) : (cls += 1) {
            vec[cls] = @intCast(dfa.states[s].trans[rep[cls]]);
        }
        var existing: ?u16 = null;
        for (rows.items, 0..) |prev, i| {
            if (std.mem.eql(i16, prev, vec)) {
                existing = @intCast(i);
                break;
            }
        }
        if (existing) |i| {
            row[s] = i;
        } else {
            row[s] = @intCast(rows.items.len);
            try rows.append(vec);
        }
    }

    const nrows: u16 = @intCast(rows.items.len);
    var nxt = try alloc.alloc(i16, @as(usize, nrows) * nclass);
    for (rows.items, 0..) |vec, i| {
        @memcpy(nxt[i * nclass ..][0..nclass], vec);
    }

    return .{
        .ec = ec,
        .nclass = nclass,
        .row = row,
        .nrows = nrows,
        .nxt = nxt,
    };
}

test "packed next matches full table" {
    const lexfile = @import("lexfile.zig");
    const nfa_mod = @import("nfa.zig");
    const diag = @import("diag.zig");

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var d = diag.Diag{};
    const spec = try lexfile.parse(alloc, &d, "t.l",
        \\%%
        \\[0-9]+ { return 1; }
        \\"+"|"-" { return 2; }
        \\.
        \\
    );
    const nfa = try nfa_mod.build(alloc, &d, &spec);
    const dfa = try dfa_mod.build(alloc, &d, &nfa, spec.tables.states);
    const p = try pack(alloc, &dfa);
    try std.testing.expect(p.nclass < 256);
    for (dfa.states, 0..) |st, si| {
        var c: u16 = 0;
        while (c < 256) : (c += 1) {
            try std.testing.expectEqual(st.trans[c], p.next(@intCast(si), @truncate(c)));
        }
    }
}
