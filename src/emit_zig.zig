const std = @import("std");
const lexfile = @import("lexfile.zig");
const dfa_mod = @import("dfa.zig");
const compress_mod = @import("compress.zig");

fn writeZigString(w: anytype, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '\\' => try w.writeAll("\\\\"),
            '"' => try w.writeAll("\\\""),
            '\n' => try w.writeAll("\\n"),
            '\t' => try w.writeAll("\\t"),
            '\r' => try w.writeAll("\\r"),
            else => try w.writeByte(c),
        }
    }
    try w.writeByte('"');
}

fn cFmtToZig(alloc: std.mem.Allocator, fmt: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    var i: usize = 0;
    while (i < fmt.len) {
        if (fmt[i] == '%' and i + 1 < fmt.len) {
            const n = fmt[i + 1];
            switch (n) {
                '%' => {
                    try out.appendSlice("%%");
                    i += 2;
                },
                's' => {
                    try out.appendSlice("{s}");
                    i += 2;
                },
                'c' => {
                    try out.appendSlice("{c}");
                    i += 2;
                },
                'd', 'i', 'u' => {
                    try out.appendSlice("{d}");
                    i += 2;
                },
                'l' => {
                    try out.appendSlice("{d}");
                    i += 2;
                    if (i < fmt.len and (fmt[i] == 'd' or fmt[i] == 'u')) i += 1;
                },
                'g', 'f' => {
                    try out.appendSlice("{d}");
                    i += 2;
                },
                else => {
                    try out.append('%');
                    i += 1;
                },
            }
        } else if (fmt[i] == '{') {
            try out.appendSlice("{{");
            i += 1;
        } else if (fmt[i] == '}') {
            try out.appendSlice("}}");
            i += 1;
        } else {
            try out.append(fmt[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice();
}

fn skipWs(s: []const u8, i: *usize) void {
    while (i.* < s.len and std.ascii.isWhitespace(s[i.*])) i.* += 1;
}

fn writeReplacedIdent(w: anytype, s: []const u8) !void {
    var i: usize = 0;
    while (i < s.len) {
        if (std.mem.startsWith(u8, s[i..], "*yytext")) {
            try w.writeAll("yytext[0]");
            i += 7;
        } else {
            try w.writeByte(s[i]);
            i += 1;
        }
    }
}

fn takeCString(alloc: std.mem.Allocator, s: []const u8, quote: usize) !struct { bytes: []u8, next: usize } {
    var i = quote + 1;
    var out = std.ArrayList(u8).init(alloc);
    while (i < s.len) {
        if (s[i] == '\\' and i + 1 < s.len) {
            const e = s[i + 1];
            try out.append(switch (e) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                'a' => 0x07,
                'b' => 0x08,
                'f' => 0x0c,
                'v' => 0x0b,
                else => e,
            });
            i += 2;
            continue;
        }
        if (s[i] == '"') return .{ .bytes = try out.toOwnedSlice(), .next = i + 1 };
        try out.append(s[i]);
        i += 1;
    }
    return error.BadString;
}

fn writeZigPrintf(alloc: std.mem.Allocator, w: anytype, action: []const u8, start: usize) !usize {
    var i = start + 6;
    skipWs(action, &i);
    if (i >= action.len or action[i] != '(') {
        try w.writeAll("printf");
        return start + 6;
    }
    i += 1;
    skipWs(action, &i);
    if (i >= action.len or action[i] != '"') {
        try w.writeAll("printf");
        return start + 6;
    }
    const taken = takeCString(alloc, action, i) catch {
        try w.writeAll("printf");
        return start + 6;
    };
    i = taken.next;
    skipWs(action, &i);
    var args: []const u8 = "";
    if (i < action.len and action[i] == ',') {
        i += 1;
        const args_start = i;
        var depth: u32 = 1;
        var j = i;
        while (j < action.len and depth > 0) : (j += 1) {
            if (action[j] == '(') depth += 1;
            if (action[j] == ')') {
                depth -= 1;
                if (depth == 0) break;
            }
        }
        args = std.mem.trim(u8, action[args_start..j], " \t\r\n");
        i = j;
    }
    if (i >= action.len or action[i] != ')') {
        try w.writeAll("printf");
        return start + 6;
    }
    i += 1;

    const zig_fmt = try cFmtToZig(alloc, taken.bytes);
    try w.writeAll("yy_print(");
    try writeZigString(w, zig_fmt);
    try w.writeAll(", .{");
    if (args.len > 0) try writeReplacedIdent(w, args);
    try w.writeAll("})");
    return i;
}

fn writeZigAction(alloc: std.mem.Allocator, w: anytype, action: []const u8) !void {
    var i: usize = 0;
    while (i < action.len) {
        if (std.mem.startsWith(u8, action[i..], "printf") and
            (i == 0 or !std.ascii.isAlphanumeric(action[i - 1])))
        {
            i = try writeZigPrintf(alloc, w, action, i);
            continue;
        }
        if (std.mem.startsWith(u8, action[i..], "BEGIN") and
            (i == 0 or !std.ascii.isAlphanumeric(action[i - 1])))
        {
            try w.writeAll("yy_start = ");
            i += 5;
            skipWs(action, &i);
            continue;
        }
        if (std.mem.startsWith(u8, action[i..], "REJECT") and
            (i == 0 or !std.ascii.isAlphanumeric(action[i - 1])))
        {
            try w.writeAll("yy_do_reject = true");
            i += 6;
            continue;
        }
        if (std.mem.startsWith(u8, action[i..], "ECHO") and
            (i == 0 or !std.ascii.isAlphanumeric(action[i - 1])))
        {
            try w.writeAll("yy_echo()");
            i += 4;
            continue;
        }
        if (std.mem.startsWith(u8, action[i..], "*yytext")) {
            try w.writeAll("yytext[0]");
            i += 7;
            continue;
        }
        try w.writeByte(action[i]);
        i += 1;
    }
}

fn writeIntRow(w: anytype, items: []const i32) !void {
    for (items, 0..) |v, i| {
        if (i != 0) try w.writeAll(",");
        try w.print("{d}", .{v});
    }
}

pub fn generate(alloc: std.mem.Allocator, spec: *const lexfile.Spec, dfa: *const dfa_mod.Dfa, compress: bool) ![]u8 {
    var buf = std.ArrayList(u8).init(alloc);
    const w = buf.writer();

    try w.writeAll(
        \\// Generated by ft_lex (-z)
        \\const std = @import("std");
        \\
        \\pub const INITIAL: i32 = 0;
        \\
    );
    for (spec.scs, 0..) |sc, i| {
        if (i == 0) continue;
        try w.print("pub const {s}: i32 = {d};\n", .{ sc.name, i });
    }

    try w.writeAll(
        \\
        \\pub var yyleng: i32 = 0;
        \\pub var yytext: []u8 = &.{};
        \\pub var yy_start: i32 = 0;
        \\var yy_bol: bool = true;
        \\var yy_buf: std.ArrayList(u8) = undefined;
        \\var yy_pos: usize = 0;
        \\var yy_more_flag: bool = false;
        \\var yy_more_len: i32 = 0;
        \\var yy_in: std.fs.File = undefined;
        \\var yy_out: std.fs.File.Writer = undefined;
        \\var yy_ready: bool = false;
        \\
        \\const Cand = struct { rule: i32, end: usize, cut: usize, len: usize };
        \\
    );

    try w.print("const yy_n_rules: usize = {d};\n", .{dfa.n_rules});
    try w.writeAll("const yy_sc_tbl = [_][2]i32{\n");
    for (0..dfa.n_sc) |sc| {
        try w.print("    .{{ {d}, {d} }},\n", .{ dfa.starts[sc][0], dfa.starts[sc][1] });
    }
    try w.writeAll("};\n");

    try w.writeAll("const yy_rule_dollar = [_]bool{");
    for (0..dfa.n_rules) |i| {
        if (i != 0) try w.writeAll(",");
        try w.print("{}", .{dfa.rule_dollar[i]});
    }
    if (dfa.n_rules == 0) try w.writeAll("false");
    try w.writeAll("};\n");

    try w.writeAll("const yy_rule_tc = [_]bool{");
    for (0..dfa.n_rules) |i| {
        if (i != 0) try w.writeAll(",");
        try w.print("{}", .{dfa.rule_tc[i]});
    }
    if (dfa.n_rules == 0) try w.writeAll("false");
    try w.writeAll("};\n");

    if (compress) {
        const packed_tbl = try compress_mod.pack(alloc, dfa);
        try w.writeAll("const yy_ec = [_]u8{");
        for (packed_tbl.ec, 0..) |v, i| {
            if (i != 0) try w.writeAll(",");
            try w.print("{d}", .{v});
        }
        try w.writeAll("};\n");
        try w.writeAll("const yy_row = [_]u16{");
        for (packed_tbl.row, 0..) |v, i| {
            if (i != 0) try w.writeAll(",");
            try w.print("{d}", .{v});
        }
        try w.writeAll("};\n");
        try w.print("const yy_nxt = [_][{d}]i16{{\n", .{packed_tbl.nclass});
        var r: usize = 0;
        while (r < packed_tbl.nrows) : (r += 1) {
            try w.writeAll("    .{");
            var c: usize = 0;
            while (c < packed_tbl.nclass) : (c += 1) {
                if (c != 0) try w.writeAll(",");
                try w.print("{d}", .{packed_tbl.nxt[r * packed_tbl.nclass + c]});
            }
            try w.writeAll("},\n");
        }
        try w.writeAll("};\n");
        try w.writeAll("fn yy_next(state: i32, c: u8) i32 { return yy_nxt[yy_row[@intCast(state)]][yy_ec[c]]; }\n");
    } else {
        try w.writeAll("const yy_nxt = [_][256]i32{\n");
        for (dfa.states) |st| {
            try w.writeAll("    .{");
            try writeIntRow(w, &st.trans);
            try w.writeAll("},\n");
        }
        try w.writeAll("};\n");
        try w.writeAll("fn yy_next(state: i32, c: u8) i32 { return yy_nxt[@intCast(state)][c]; }\n");
    }

    try w.writeAll("const yy_naccept = [_]usize{");
    for (dfa.states, 0..) |st, i| {
        if (i != 0) try w.writeAll(",");
        try w.print("{d}", .{st.accepts.len});
    }
    try w.writeAll("};\n");

    try w.writeAll("const yy_acc_off = [_]usize{");
    var off: usize = 0;
    for (dfa.states, 0..) |st, i| {
        if (i != 0) try w.writeAll(",");
        try w.print("{d}", .{off});
        off += st.accepts.len;
    }
    try w.writeAll("};\n");

    try w.writeAll("const yy_acc_list = [_]i32{");
    var first = true;
    for (dfa.states) |st| {
        for (st.accepts) |a| {
            if (!first) try w.writeAll(",");
            first = false;
            try w.print("{d}", .{a});
        }
    }
    if (first) try w.writeAll("0");
    try w.writeAll("};\n");

    try w.writeAll("const yy_ncut = [_]usize{");
    for (dfa.states, 0..) |st, i| {
        if (i != 0) try w.writeAll(",");
        try w.print("{d}", .{st.cuts.len});
    }
    try w.writeAll("};\n");

    try w.writeAll("const yy_cut_off = [_]usize{");
    off = 0;
    for (dfa.states, 0..) |st, i| {
        if (i != 0) try w.writeAll(",");
        try w.print("{d}", .{off});
        off += st.cuts.len;
    }
    try w.writeAll("};\n");

    try w.writeAll("const yy_cut_list = [_]i32{");
    first = true;
    for (dfa.states) |st| {
        for (st.cuts) |a| {
            if (!first) try w.writeAll(",");
            first = false;
            try w.print("{d}", .{a});
        }
    }
    if (first) try w.writeAll("0");
    try w.writeAll("};\n\n");

    if (spec.header.len > 0) {
        try w.writeAll(spec.header);
        try w.writeAll("\n\n");
    }

    try w.writeAll(
        \\fn yy_print(comptime fmt: []const u8, args: anytype) void {
        \\    yy_out.print(fmt, args) catch {};
        \\}
        \\
        \\fn yy_echo() void {
        \\    _ = yy_out.write(yytext) catch {};
        \\}
        \\
        \\fn yywrap() bool {
        \\    return true;
        \\}
        \\
        \\fn yy_ensure() void {
        \\    if (yy_ready) return;
        \\    yy_buf = std.ArrayList(u8).init(std.heap.page_allocator);
        \\    yy_in = std.io.getStdIn();
        \\    yy_out = std.io.getStdOut().writer();
        \\    yy_start = INITIAL;
        \\    yy_bol = true;
        \\    yy_ready = true;
        \\}
        \\
        \\fn yy_char_at(p: usize) i32 {
        \\    while (p >= yy_buf.items.len) {
        \\        var tmp: [256]u8 = undefined;
        \\        const n = yy_in.read(&tmp) catch return -1;
        \\        if (n == 0) return -1;
        \\        yy_buf.appendSlice(tmp[0..n]) catch return -1;
        \\    }
        \\    return yy_buf.items[p];
        \\}
        \\
        \\fn yy_compact() void {
        \\    if (yy_pos == 0) return;
        \\    const n = yy_buf.items.len - yy_pos;
        \\    if (n > 0) std.mem.copyForwards(u8, yy_buf.items[0..n], yy_buf.items[yy_pos..]);
        \\    yy_buf.shrinkRetainingCapacity(n);
        \\    yy_pos = 0;
        \\}
        \\
        \\fn yy_match_ok(rule: i32, end: usize) bool {
        \\    if (rule < 0) return false;
        \\    if (!yy_rule_dollar[@intCast(rule)]) return true;
        \\    const c = yy_char_at(end);
        \\    return c < 0 or c == '\n';
        \\}
        \\
        \\fn yy_add_cand(cands: *[64]Cand, ncand: *usize, rule: i32, end: usize, cut: usize, start: usize) void {
        \\    if (rule < 0 or !yy_match_ok(rule, end)) return;
        \\    const len: usize = if (yy_rule_tc[@intCast(rule)]) cut - start else end - start;
        \\    if (len == 0) return;
        \\    var i: usize = 0;
        \\    while (i < ncand.*) : (i += 1) {
        \\        if (cands[i].rule == rule and cands[i].end == end) return;
        \\    }
        \\    if (ncand.* >= 64) return;
        \\    cands[ncand.*] = .{ .rule = rule, .end = end, .cut = cut, .len = len };
        \\    ncand.* += 1;
        \\}
        \\
        \\fn yy_collect(state: i32, start: usize, p: usize, cuts: []usize, cands: *[64]Cand, ncand: *usize) void {
        \\    const st: usize = @intCast(state);
        \\    var i: usize = 0;
        \\    while (i < yy_ncut[st]) : (i += 1) {
        \\        const r = yy_cut_list[yy_cut_off[st] + i];
        \\        if (r >= 0) cuts[@intCast(r)] = p;
        \\    }
        \\    i = 0;
        \\    while (i < yy_naccept[st]) : (i += 1) {
        \\        const r = yy_acc_list[yy_acc_off[st] + i];
        \\        yy_add_cand(cands, ncand, r, p, cuts[@intCast(r)], start);
        \\    }
        \\}
        \\
        \\fn candLess(_: void, a: Cand, b: Cand) bool {
        \\    if (a.len != b.len) return a.len > b.len;
        \\    return a.rule < b.rule;
        \\}
        \\
        \\pub fn yylex() i32 {
        \\    yy_ensure();
        \\
    );

    if (spec.local.len > 0) {
        try w.writeAll(spec.local);
        try w.writeAll("\n");
    }

    try w.writeAll(
        \\    var reject_n: usize = 0;
        \\    var saved: [64]Cand = undefined;
        \\    var saved_n: usize = 0;
        \\    var saved_start: usize = 0;
        \\    var saved_more: i32 = 0;
        \\
        \\    while (true) {
        \\        if (!yy_more_flag) yy_compact();
        \\        const more: i32 = if (yy_more_flag) yy_more_len else 0;
        \\        yy_more_flag = false;
        \\        var start = yy_pos;
        \\
        \\        if (reject_n == 0) {
        \\            var cuts_buf: [64]usize = undefined;
        \\            const cuts = cuts_buf[0..@min(yy_n_rules, cuts_buf.len)];
        \\            for (cuts) |*x| x.* = start;
        \\            var cands: [64]Cand = undefined;
        \\            var ncand: usize = 0;
        \\            var state: i32 = yy_sc_tbl[@intCast(yy_start)][if (yy_bol) 1 else 0];
        \\            yy_collect(state, start, start, cuts, &cands, &ncand);
        \\            var p = start;
        \\            while (true) {
        \\                const ch = yy_char_at(p);
        \\                if (ch < 0) break;
        \\                const ns = yy_next(state, @intCast(ch));
        \\                if (ns < 0) break;
        \\                state = ns;
        \\                p += 1;
        \\                yy_collect(state, start, p, cuts, &cands, &ncand);
        \\            }
        \\            std.mem.sort(Cand, cands[0..ncand], {}, candLess);
        \\            saved = cands;
        \\            saved_n = ncand;
        \\            saved_start = start;
        \\            saved_more = more;
        \\        } else {
        \\            start = saved_start;
        \\        }
        \\
        \\        if (saved_n <= reject_n) {
        \\            reject_n = 0;
        \\            if (yy_char_at(start) < 0) {
        \\                if (yywrap()) return 0;
        \\                continue;
        \\            }
        \\            const ch: u8 = @intCast(yy_char_at(start));
        \\            _ = yy_out.write(&.{ch}) catch {};
        \\            yy_pos = start + 1;
        \\            yy_bol = ch == '\n';
        \\            continue;
        \\        }
        \\
        \\        const chs = saved[reject_n];
        \\        var end = chs.end;
        \\        if (yy_rule_tc[@intCast(chs.rule)]) end = chs.cut;
        \\        yy_pos = end;
        \\        if (end > start) yy_bol = yy_buf.items[end - 1] == '\n';
        \\        yyleng = more + @as(i32, @intCast(end - start));
        \\        const tok_start = start - @as(usize, @intCast(more));
        \\        yytext = yy_buf.items[tok_start..end];
        \\        var yy_do_reject: bool = undefined;
        \\        yy_do_reject = false;
        \\
        \\        switch (chs.rule) {
        \\
    );

    for (spec.rules, 0..) |rule, i| {
        try w.print("            {d} => {{\n", .{i});
        const action = std.mem.trim(u8, rule.action, " \t\r\n");
        if (action.len > 0) {
            try w.writeAll("                ");
            try writeZigAction(alloc, w, action);
            try w.writeAll("\n");
        }
        try w.writeAll("            },\n");
    }

    try w.writeAll(
        \\            else => {},
        \\        }
        \\        if (yy_do_reject) {
        \\            reject_n += 1;
        \\            yy_pos = saved_start;
        \\            continue;
        \\        }
        \\        reject_n = 0;
        \\    }
        \\}
        \\
    );

    if (spec.user.len > 0) {
        try w.writeAll(spec.user);
        try w.writeAll("\n");
    } else {
        try w.writeAll(
            \\pub fn main() !void {
            \\    _ = yylex();
            \\}
            \\
        );
    }

    return buf.toOwnedSlice();
}
