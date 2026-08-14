const std = @import("std");
const diag = @import("diag.zig");
const nfa_mod = @import("nfa.zig");

pub const DState = struct {
    trans: [256]i32,
    accepts: []i32,
    cuts: []i32,
};

pub const Dfa = struct {
    states: []DState,
    starts: [][2]u32,
    n_rules: u32,
    n_sc: u32,
    rule_dollar: []const bool,
    rule_tc: []const bool,
    nfa_states: u32,
};

const SetCtx = struct {
    pub fn hash(_: SetCtx, k: []const u32) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(std.mem.sliceAsBytes(k));
        return h.final();
    }
    pub fn eql(_: SetCtx, a: []const u32, b: []const u32) bool {
        return std.mem.eql(u32, a, b);
    }
};

fn eclosure(alloc: std.mem.Allocator, nfa: *const nfa_mod.Nfa, seeds: []const u32) ![]u32 {
    const n = nfa.states.items.len;
    const seen = try alloc.alloc(bool, n);
    @memset(seen, false);
    var stack = std.ArrayList(u32).init(alloc);
    var out = std.ArrayList(u32).init(alloc);
    for (seeds) |s| {
        if (s < n and !seen[s]) {
            seen[s] = true;
            try stack.append(s);
        }
    }
    while (stack.pop()) |s| {
        try out.append(s);
        for (nfa.states.items[s].trans.items) |t| {
            if (t.kind == .eps and !seen[t.to]) {
                seen[t.to] = true;
                try stack.append(t.to);
            }
        }
    }
    std.mem.sort(u32, out.items, {}, std.sort.asc(u32));
    return out.toOwnedSlice();
}

fn moveInto(nfa: *const nfa_mod.Nfa, set: []const u32, c: u8, dest: *std.ArrayList(u32)) !void {
    dest.clearRetainingCapacity();
    for (set) |s| {
        for (nfa.states.items[s].trans.items) |t| {
            const ok = switch (t.kind) {
                .eps => false,
                .byte => t.c == c,
                .class => t.class.?.has(c),
            };
            if (ok) try dest.append(t.to);
        }
    }
}

fn collectIds(alloc: std.mem.Allocator, nfa: *const nfa_mod.Nfa, set: []const u32, comptime field: []const u8) ![]i32 {
    var tmp = std.ArrayList(i32).init(alloc);
    for (set) |s| {
        const id = @field(nfa.states.items[s], field);
        if (id >= 0) {
            var exists = false;
            for (tmp.items) |x| {
                if (x == id) {
                    exists = true;
                    break;
                }
            }
            if (!exists) try tmp.append(id);
        }
    }
    std.mem.sort(i32, tmp.items, {}, std.sort.asc(i32));
    return tmp.toOwnedSlice();
}

pub fn build(alloc: std.mem.Allocator, d: *diag.Diag, nfa: *const nfa_mod.Nfa, max_states: usize) !Dfa {
    var map = std.HashMap([]const u32, u32, SetCtx, 80).init(alloc);
    var states = std.ArrayList(DState).init(alloc);
    var work = std.ArrayList(u32).init(alloc);
    var move_buf = std.ArrayList(u32).init(alloc);

    const starts = try alloc.alloc([2]u32, nfa.n_sc);
    var sc: u32 = 0;
    while (sc < nfa.n_sc) : (sc += 1) {
        var bol: u32 = 0;
        while (bol < 2) : (bol += 1) {
            const seed = [_]u32{nfa.starts[sc][bol]};
            const set = try eclosure(alloc, nfa, &seed);
            if (map.get(set)) |id| {
                starts[sc][bol] = id;
            } else {
                const id: u32 = @intCast(states.items.len);
                if (id >= max_states) {
                    d.set(1, 1, "too many DFA states (increase %n to at least {d})", .{id + 1});
                    return error.CompileFail;
                }
                try map.put(set, id);
                try states.append(.{
                    .trans = [_]i32{-1} ** 256,
                    .accepts = try collectIds(alloc, nfa, set, "accept"),
                    .cuts = try collectIds(alloc, nfa, set, "tc_cut"),
                });
                try work.append(id);
                starts[sc][bol] = id;
            }
        }
    }

    var w: usize = 0;
    while (w < work.items.len) : (w += 1) {
        const did = work.items[w];
        var set_ptr: []const u32 = undefined;
        var it = map.iterator();
        while (it.next()) |e| {
            if (e.value_ptr.* == did) {
                set_ptr = e.key_ptr.*;
                break;
            }
        }

        var c: u32 = 0;
        while (c < 256) : (c += 1) {
            try moveInto(nfa, set_ptr, @truncate(c), &move_buf);
            if (move_buf.items.len == 0) continue;
            const nxt = try eclosure(alloc, nfa, move_buf.items);
            if (nxt.len == 0) continue;
            if (map.get(nxt)) |id| {
                states.items[did].trans[c] = @intCast(id);
            } else {
                const id: u32 = @intCast(states.items.len);
                if (id >= max_states) {
                    d.set(1, 1, "too many DFA states (increase %n to at least {d})", .{id + 1});
                    return error.CompileFail;
                }
                try map.put(nxt, id);
                try states.append(.{
                    .trans = [_]i32{-1} ** 256,
                    .accepts = try collectIds(alloc, nfa, nxt, "accept"),
                    .cuts = try collectIds(alloc, nfa, nxt, "tc_cut"),
                });
                try work.append(id);
                states.items[did].trans[c] = @intCast(id);
            }
        }
    }

    return .{
        .states = try states.toOwnedSlice(),
        .starts = starts,
        .n_rules = nfa.n_rules,
        .n_sc = nfa.n_sc,
        .rule_dollar = nfa.rule_dollar,
        .rule_tc = nfa.rule_tc,
        .nfa_states = @intCast(nfa.states.items.len),
    };
}

pub const Match = struct {
    rule: i32,
    len: usize,
};

pub fn matchLongest(self: *const Dfa, input: []const u8, sc: u32, bol: bool) ?Match {
    var state: i32 = @intCast(self.starts[sc][@intFromBool(bol)]);
    var best: ?Match = null;
    var i: usize = 0;
    while (i < input.len) {
        const ns = self.states[@intCast(state)].trans[input[i]];
        if (ns < 0) break;
        state = ns;
        i += 1;
        var chosen: ?i32 = null;
        for (self.states[@intCast(state)].accepts) |r| {
            if (self.rule_dollar[@intCast(r)]) {
                if (!(i == input.len or input[i] == '\n')) continue;
            }
            chosen = r;
            break;
        }
        if (chosen) |r| best = .{ .rule = r, .len = i };
    }
    return best;
}
