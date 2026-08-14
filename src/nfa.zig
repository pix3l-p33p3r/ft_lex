const std = @import("std");
const diag = @import("diag.zig");
const lexfile = @import("lexfile.zig");
const regex = @import("regex.zig");

pub const TransKind = enum { eps, byte, class };

pub const Trans = struct {
    kind: TransKind,
    to: u32,
    c: u8 = 0,
    class: ?*const regex.Class = null,
};

pub const State = struct {
    trans: std.ArrayListUnmanaged(Trans) = .{},
    accept: i32 = -1,
    tc_cut: i32 = -1,
};

pub const Nfa = struct {
    states: std.ArrayListUnmanaged(State) = .{},
    starts: [][2]u32,
    n_rules: u32,
    n_sc: u32,
    rule_dollar: []bool,
    rule_tc: []bool,
};

const Builder = struct {
    alloc: std.mem.Allocator,
    d: *diag.Diag,
    spec: *const lexfile.Spec,
    nfa: Nfa,
    max_states: usize,

    fn newState(self: *Builder) !u32 {
        if (self.nfa.states.items.len >= self.max_states) {
            self.d.set(1, 1, "too many NFA states (increase %n)", .{});
            return error.CompileFail;
        }
        const id: u32 = @intCast(self.nfa.states.items.len);
        try self.nfa.states.append(self.alloc, .{});
        return id;
    }

    fn add(self: *Builder, from: u32, t: Trans) !void {
        try self.nfa.states.items[from].trans.append(self.alloc, t);
    }

    fn eps(self: *Builder, from: u32, to: u32) !void {
        try self.add(from, .{ .kind = .eps, .to = to });
    }

    fn frag(self: *Builder, n: *regex.Node) diag.Fail!struct { s: u32, a: u32 } {
        switch (n.kind) {
            .empty => {
                const s = try self.newState();
                const a = try self.newState();
                try self.eps(s, a);
                return .{ .s = s, .a = a };
            },
            .byte => {
                const s = try self.newState();
                const a = try self.newState();
                try self.add(s, .{ .kind = .byte, .to = a, .c = n.c });
                return .{ .s = s, .a = a };
            },
            .class => {
                const s = try self.newState();
                const a = try self.newState();
                try self.add(s, .{ .kind = .class, .to = a, .class = n.class.? });
                return .{ .s = s, .a = a };
            },
            .concat => {
                const l = try self.frag(n.left.?);
                const r = try self.frag(n.right.?);
                try self.eps(l.a, r.s);
                return .{ .s = l.s, .a = r.a };
            },
            .alt => {
                const s = try self.newState();
                const a = try self.newState();
                const l = try self.frag(n.left.?);
                const r = try self.frag(n.right.?);
                try self.eps(s, l.s);
                try self.eps(s, r.s);
                try self.eps(l.a, a);
                try self.eps(r.a, a);
                return .{ .s = s, .a = a };
            },
            .star => {
                const s = try self.newState();
                const a = try self.newState();
                const i = try self.frag(n.left.?);
                try self.eps(s, i.s);
                try self.eps(s, a);
                try self.eps(i.a, i.s);
                try self.eps(i.a, a);
                return .{ .s = s, .a = a };
            },
            .plus => {
                const s = try self.newState();
                const a = try self.newState();
                const i = try self.frag(n.left.?);
                try self.eps(s, i.s);
                try self.eps(i.a, i.s);
                try self.eps(i.a, a);
                return .{ .s = s, .a = a };
            },
            .opt => {
                const s = try self.newState();
                const a = try self.newState();
                const i = try self.frag(n.left.?);
                try self.eps(s, i.s);
                try self.eps(s, a);
                try self.eps(i.a, a);
                return .{ .s = s, .a = a };
            },
        }
    }

    fn ruleActive(self: *Builder, rule: lexfile.Rule, sc: u32, bol: bool) bool {
        if (rule.bol and !bol) return false;
        if (rule.scs.len == 0) {
            return !self.spec.scs[sc].exclusive;
        }
        for (rule.scs) |id| {
            if (id == sc) return true;
        }
        return false;
    }

    fn build(self: *Builder) !Nfa {
        const n_sc: u32 = @intCast(self.spec.scs.len);
        const n_rules: u32 = @intCast(self.spec.rules.len);
        self.nfa.n_sc = n_sc;
        self.nfa.n_rules = n_rules;
        self.nfa.starts = try self.alloc.alloc([2]u32, n_sc);
        self.nfa.rule_dollar = try self.alloc.alloc(bool, n_rules);
        self.nfa.rule_tc = try self.alloc.alloc(bool, n_rules);

        for (self.spec.rules, 0..) |rule, ri| {
            self.nfa.rule_dollar[ri] = rule.dollar;
            self.nfa.rule_tc[ri] = rule.trailing != null;
        }

        var sc: u32 = 0;
        while (sc < n_sc) : (sc += 1) {
            var bol_i: u32 = 0;
            while (bol_i < 2) : (bol_i += 1) {
                const start = try self.newState();
                self.nfa.starts[sc][bol_i] = start;
                for (self.spec.rules, 0..) |rule, ri| {
                    if (!self.ruleActive(rule, sc, bol_i == 1)) continue;
                    const ast = try regex.parseEre(self.alloc, self.d, self.spec.defs, rule.pattern, rule.line);
                    const f = try self.frag(ast);
                    try self.eps(start, f.s);
                    const rid: i32 = @intCast(ri);
                    if (rule.trailing) |tr| {
                        self.nfa.states.items[f.a].tc_cut = rid;
                        const tast = try regex.parseEre(self.alloc, self.d, self.spec.defs, tr, rule.line);
                        const tf = try self.frag(tast);
                        try self.eps(f.a, tf.s);
                        self.nfa.states.items[tf.a].accept = rid;
                    } else {
                        self.nfa.states.items[f.a].accept = rid;
                    }
                }
            }
        }
        return self.nfa;
    }
};

pub fn build(alloc: std.mem.Allocator, d: *diag.Diag, spec: *const lexfile.Spec) !Nfa {
    var b = Builder{
        .alloc = alloc,
        .d = d,
        .spec = spec,
        .nfa = .{
            .starts = undefined,
            .n_rules = 0,
            .n_sc = 0,
            .rule_dollar = undefined,
            .rule_tc = undefined,
        },
        .max_states = spec.tables.states * 8,
    };
    return b.build();
}
