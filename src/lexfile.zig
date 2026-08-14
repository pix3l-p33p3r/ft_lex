const std = @import("std");
const diag = @import("diag.zig");

pub const Definition = struct {
    name: []const u8,
    subst: []const u8,
};

pub const StartCond = struct {
    name: []const u8,
    exclusive: bool,
};

pub const Rule = struct {
    /// Empty: active in every inclusive start condition.
    scs: []u32,
    bol: bool,
    dollar: bool,
    pattern: []const u8,
    trailing: ?[]const u8,
    action: []const u8,
    line: u32,
    share_next: bool,
};

pub const TableSizes = struct {
    positions: usize = 2500,
    states: usize = 8000,
    transitions: usize = 20000,
    parse_nodes: usize = 10000,
    packed_cc: usize = 1000,
    output: usize = 30000,
    specified: bool = false,
};

pub const Spec = struct {
    header: []const u8,
    local: []const u8,
    user: []const u8,
    defs: []Definition,
    scs: []StartCond,
    rules: []Rule,
    yytext_array: bool = false,
    tables: TableSizes = .{},
};

const Parser = struct {
    alloc: std.mem.Allocator,
    d: *diag.Diag,
    src: []const u8,
    i: usize = 0,
    line: u32 = 1,
    col: u32 = 1,

    fn fail(self: *Parser, comptime fmt: []const u8, args: anytype) diag.Fail {
        self.d.set(self.line, self.col, fmt, args);
        return error.CompileFail;
    }

    fn failAt(self: *Parser, line: u32, col: u32, comptime fmt: []const u8, args: anytype) diag.Fail {
        self.d.set(line, col, fmt, args);
        return error.CompileFail;
    }

    fn peek(self: *const Parser) ?u8 {
        if (self.i >= self.src.len) return null;
        return self.src[self.i];
    }

    fn peekAt(self: *const Parser, off: usize) ?u8 {
        if (self.i + off >= self.src.len) return null;
        return self.src[self.i + off];
    }

    fn next(self: *Parser) ?u8 {
        const c = self.peek() orelse return null;
        self.i += 1;
        if (c == '\n') {
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        return c;
    }

    fn starts(self: *const Parser, s: []const u8) bool {
        if (self.i + s.len > self.src.len) return false;
        return std.mem.eql(u8, self.src[self.i .. self.i + s.len], s);
    }

    fn atLineStart(self: *const Parser) bool {
        return self.col == 1;
    }

    fn skipSpaces(self: *Parser) void {
        while (self.peek()) |c| {
            if (c != ' ' and c != '\t') break;
            _ = self.next();
        }
    }

    fn skipToEol(self: *Parser) void {
        while (self.peek()) |c| {
            if (c == '\n') break;
            _ = self.next();
        }
    }

    fn skipComment(self: *Parser) !void {
        if (!self.starts("/*")) return;
        const sl = self.line;
        const sc = self.col;
        _ = self.next();
        _ = self.next();
        while (self.peek()) |_| {
            if (self.starts("*/")) {
                _ = self.next();
                _ = self.next();
                return;
            }
            _ = self.next();
        }
        return self.failAt(sl, sc, "unterminated comment", .{});
    }

    fn skipWsAndComments(self: *Parser) !void {
        while (true) {
            const c = self.peek() orelse return;
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                _ = self.next();
                continue;
            }
            if (self.starts("/*")) {
                try self.skipComment();
                continue;
            }
            return;
        }
    }

    fn restOfLine(self: *Parser) []const u8 {
        const start = self.i;
        self.skipToEol();
        return std.mem.trimRight(u8, self.src[start..self.i], " \t\r");
    }

    fn takeIdent(self: *Parser) ![]const u8 {
        const c0 = self.peek() orelse return self.fail("unexpected end of file", .{});
        if (!(std.ascii.isAlphabetic(c0) or c0 == '_')) {
            return self.fail("unexpected token '{c}'", .{c0});
        }
        const start = self.i;
        _ = self.next();
        while (self.peek()) |c| {
            if (!(std.ascii.isAlphanumeric(c) or c == '_')) break;
            _ = self.next();
        }
        return self.src[start..self.i];
    }

    fn takeNumber(self: *Parser) !usize {
        const start = self.i;
        while (self.peek()) |c| {
            if (!std.ascii.isDigit(c)) break;
            _ = self.next();
        }
        if (start == self.i) return self.fail("expected number", .{});
        return std.fmt.parseInt(usize, self.src[start..self.i], 10) catch {
            return self.fail("bad number", .{});
        };
    }

    fn copyLineAsC(self: *Parser, out: *std.ArrayList(u8)) !void {
        if (out.items.len > 0) try out.append('\n');
        const line = self.restOfLine();
        try out.appendSlice(line);
        if (self.peek() == '\n') _ = self.next();
    }

    fn copyCBlock(self: *Parser, out: *std.ArrayList(u8)) !void {
        // caller saw "%{" at line start
        const sl = self.line;
        self.skipToEol();
        if (self.peek() == '\n') _ = self.next();
        const start = self.i;
        while (self.peek()) |_| {
            if (self.atLineStart() and (self.starts("%}") or self.starts(" %}")) ) {
                // allow optional spaces before %}
                const save_i = self.i;
                const save_line = self.line;
                const save_col = self.col;
                self.skipSpaces();
                if (self.starts("%}")) {
                    const end = save_i;
                    if (out.items.len > 0) try out.append('\n');
                    try out.appendSlice(std.mem.trimRight(u8, self.src[start..end], " \t\r\n"));
                    _ = self.next();
                    _ = self.next();
                    self.skipToEol();
                    if (self.peek() == '\n') _ = self.next();
                    return;
                }
                self.i = save_i;
                self.line = save_line;
                self.col = save_col;
            }
            _ = self.next();
        }
        return self.failAt(sl, 1, "unterminated %{{ block", .{});
    }

    fn parsePercent(self: *Parser, spec_scs: *std.ArrayList(StartCond), tables: *TableSizes, yytext_array: *bool, header: *std.ArrayList(u8)) !enum { section, more } {
        const sl = self.line;
        _ = self.next(); // %
        const c = self.peek() orelse return self.fail("unexpected end of file", .{});
        if (c == '%') {
            _ = self.next();
            self.skipToEol();
            if (self.peek() == '\n') _ = self.next();
            return .section;
        }
        if (c == '{') {
            try self.copyCBlock(header);
            return .more;
        }

        const word_start = self.i;
        while (self.peek()) |ch| {
            if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) break;
            _ = self.next();
        }
        const word = self.src[word_start..self.i];
        if (word.len == 0) return self.failAt(sl, 1, "unrecognized '%' directive", .{});

        if (std.mem.eql(u8, word, "array")) {
            yytext_array.* = true;
            self.skipToEol();
            if (self.peek() == '\n') _ = self.next();
            return .more;
        }
        if (std.mem.eql(u8, word, "pointer")) {
            yytext_array.* = false;
            self.skipToEol();
            if (self.peek() == '\n') _ = self.next();
            return .more;
        }

        const first = word[0];
        if (first == 's' or first == 'S' or first == 'x' or first == 'X') {
            const exclusive = first == 'x' or first == 'X';
            self.skipSpaces();
            while (self.peek()) |ch| {
                if (ch == '\n') break;
                if (ch == ' ' or ch == '\t') {
                    self.skipSpaces();
                    continue;
                }
                const name = try self.takeIdent();
                if (std.ascii.eqlIgnoreCase(name, "INITIAL")) {
                    return self.failAt(sl, 1, "invalid start condition: \"INITIAL\" is already defined", .{});
                }
                try spec_scs.append(.{ .name = name, .exclusive = exclusive });
                self.skipSpaces();
            }
            if (self.peek() == '\n') _ = self.next();
            return .more;
        }

        if (word.len == 1 and std.mem.indexOfScalar(u8, "pnaeko", first) != null) {
            self.skipSpaces();
            const n = try self.takeNumber();
            tables.specified = true;
            switch (first) {
                'p' => tables.positions = n,
                'n' => tables.states = n,
                'a' => tables.transitions = n,
                'e' => tables.parse_nodes = n,
                'k' => tables.packed_cc = n,
                'o' => tables.output = n,
                else => {},
            }
            self.skipToEol();
            if (self.peek() == '\n') _ = self.next();
            return .more;
        }

        return self.failAt(sl, 1, "unrecognized '%' directive", .{});
    }

    fn parseDefinition(self: *Parser, defs: *std.ArrayList(Definition)) !void {
        const name = try self.takeIdent();
        self.skipSpaces();
        if (self.peek() == null or self.peek() == '\n') {
            return self.fail("incomplete name definition", .{});
        }
        const subst_raw = std.mem.trim(u8, self.restOfLine(), " \t\r");
        if (self.peek() == '\n') _ = self.next();
        const subst = try std.fmt.allocPrint(self.alloc, "({s})", .{subst_raw});
        try defs.append(.{ .name = name, .subst = subst });
    }

    fn parseStartConds(self: *Parser, spec_scs: []const StartCond, out: *std.ArrayList(u32)) !void {
        _ = self.next(); // <
        while (true) {
            self.skipSpaces();
            const c = self.peek() orelse return self.fail("unterminated start condition list", .{});
            if (c == '>') {
                _ = self.next();
                return;
            }
            if (c == ',') {
                _ = self.next();
                continue;
            }
            const name = try self.takeIdent();
            var found: ?u32 = null;
            for (spec_scs, 0..) |sc, i| {
                if (std.mem.eql(u8, sc.name, name)) {
                    found = @intCast(i);
                    break;
                }
            }
            if (found == null) {
                return self.fail("invalid start condition '{s}'", .{name});
            }
            try out.append(found.?);
            self.skipSpaces();
        }
    }

    fn extractPattern(self: *Parser) !struct {
        bol: bool,
        dollar: bool,
        pattern: []const u8,
        trailing: ?[]const u8,
    } {
        var bol = false;
        if (self.peek() == '^') {
            bol = true;
            _ = self.next();
        }

        const start = self.i;
        const sl = self.line;
        var quote = false;
        var brackets: u32 = 0;
        var parens: u32 = 0;
        var slash_at: ?usize = null;

        while (self.peek()) |c| {
            if (!quote and brackets == 0 and (c == ' ' or c == '\t' or c == '\n' or c == '\r'))
                break;

            if (c == '\\') {
                _ = self.next();
                const n = self.peek() orelse return self.failAt(sl, self.col, "unexpected end of file", .{});
                if (n == '\n') return self.fail("unexpected token '\\n'", .{});
                _ = self.next();
                continue;
            }

            if (c == '"' and brackets == 0) {
                quote = !quote;
                _ = self.next();
                continue;
            }

            if (!quote) {
                if (c == '[') {
                    brackets += 1;
                    _ = self.next();
                    continue;
                }
                if (c == ']') {
                    if (brackets == 0) return self.fail("unexpected token ']'", .{});
                    brackets -= 1;
                    _ = self.next();
                    continue;
                }
                if (brackets == 0) {
                    if (c == '(') parens += 1;
                    if (c == ')') {
                        if (parens == 0) return self.fail("unexpected token ')'", .{});
                        parens -= 1;
                    }
                    if (c == '/' and parens == 0) {
                        if (slash_at != null) return self.fail("too many trailing contexts", .{});
                        slash_at = self.i;
                    }
                }
            }
            _ = self.next();
        }

        if (quote) return self.failAt(sl, 1, "unbalanced quotes", .{});
        if (brackets != 0) return self.failAt(sl, 1, "malformed bracket expression", .{});
        if (parens != 0) return self.failAt(sl, 1, "unbalanced parenthesis", .{});

        var raw = self.src[start..self.i];
        var dollar = false;
        var trailing: ?[]const u8 = null;

        if (slash_at) |sp| {
            const left = self.src[start..sp];
            const right = self.src[sp + 1 .. self.i];
            if (left.len == 0) return self.failAt(sl, 1, "empty pattern before '/'", .{});
            if (right.len == 0) return self.failAt(sl, 1, "empty trailing context", .{});
            raw = left;
            trailing = right;
        }

        if (raw.len > 0 and raw[raw.len - 1] == '$') {
            // $ is trailing-context only at the very end of the whole ERE
            dollar = true;
            raw = raw[0 .. raw.len - 1];
            if (trailing != null) return self.failAt(sl, 1, "too many trailing contexts", .{});
        }

        if (raw.len == 0) return self.failAt(sl, 1, "empty regular expression", .{});
        return .{ .bol = bol, .dollar = dollar, .pattern = raw, .trailing = trailing };
    }

    fn parseAction(self: *Parser) !struct { action: []const u8, share_next: bool } {
        self.skipSpaces();
        const c = self.peek() orelse return .{ .action = "", .share_next = false };
        if (c == '\n') return .{ .action = "", .share_next = false };

        if (c == '|') {
            const after = self.peekAt(1);
            // "|" alone (or only whitespace until EOL) shares the next rule's action.
            if (after == null or after == '\n' or after == '\r' or after == ' ' or after == '\t') {
                const save_i = self.i;
                _ = self.next();
                self.skipSpaces();
                const n = self.peek();
                if (n == null or n == '\n') {
                    if (self.peek() == '\n') _ = self.next();
                    return .{ .action = "", .share_next = true };
                }
                // same-line "| pattern action" — treat as share and continue from here
                self.i = save_i;
                _ = self.next(); // consume |
                return .{ .action = "", .share_next = true };
            }
            // "|foo" would be odd; treat as share-next + continue
            _ = self.next();
            return .{ .action = "", .share_next = true };
        }

        if (c == '{') {
            const sl = self.line;
            const start = self.i;
            var depth: u32 = 0;
            var dquote = false;
            var squote = false;
            var line_comment = false;
            var block_comment = false;
            while (self.peek()) |_| {
                if (line_comment) {
                    if (self.peek() == '\n') {
                        line_comment = false;
                    }
                    _ = self.next();
                    continue;
                }
                if (block_comment) {
                    if (self.starts("*/")) {
                        _ = self.next();
                        _ = self.next();
                        block_comment = false;
                        continue;
                    }
                    _ = self.next();
                    continue;
                }
                if (!dquote and !squote and self.starts("//")) {
                    line_comment = true;
                    _ = self.next();
                    _ = self.next();
                    continue;
                }
                if (!dquote and !squote and self.starts("/*")) {
                    block_comment = true;
                    _ = self.next();
                    _ = self.next();
                    continue;
                }
                const ch = self.peek().?;
                if (ch == '\\' and (dquote or squote)) {
                    _ = self.next();
                    _ = self.next();
                    continue;
                }
                if (ch == '"' and !squote) {
                    dquote = !dquote;
                    _ = self.next();
                    continue;
                }
                if (ch == '\'' and !dquote) {
                    squote = !squote;
                    _ = self.next();
                    continue;
                }
                if (!dquote and !squote) {
                    if (ch == '{') depth += 1;
                    if (ch == '}') {
                        depth -= 1;
                        _ = self.next();
                        if (depth == 0) {
                            const action = self.src[start..self.i];
                            self.skipToEol();
                            if (self.peek() == '\n') _ = self.next();
                            return .{ .action = action, .share_next = false };
                        }
                        continue;
                    }
                }
                _ = self.next();
            }
            return self.failAt(sl, 1, "unterminated action", .{});
        }

        const action = self.restOfLine();
        if (self.peek() == '\n') _ = self.next();
        return .{ .action = action, .share_next = false };
    }

    fn parseRule(self: *Parser, spec_scs: []const StartCond, rules: *std.ArrayList(Rule)) !void {
        const line = self.line;
        var scs = std.ArrayList(u32).init(self.alloc);
        if (self.peek() == '<') {
            try self.parseStartConds(spec_scs, &scs);
        }

        // One logical line may be `"+" | "-" | "/" printf(...)`.
        while (true) {
            const pat = try self.extractPattern();
            const act = try self.parseAction();
            try rules.append(.{
                .scs = if (scs.items.len == 0) &.{} else try self.alloc.dupe(u32, scs.items),
                .bol = pat.bol,
                .dollar = pat.dollar,
                .pattern = pat.pattern,
                .trailing = pat.trailing,
                .action = act.action,
                .line = line,
                .share_next = act.share_next,
            });
            if (!act.share_next) break;
            self.skipSpaces();
            const n = self.peek() orelse break;
            if (n == '\n') {
                _ = self.next();
                break;
            }
            // continue parsing the next pattern on this line
        }
    }

    fn resolveShares(self: *Parser, rules: []Rule) !void {
        var i: usize = rules.len;
        while (i > 0) {
            i -= 1;
            if (!rules[i].share_next) continue;
            if (i + 1 >= rules.len) {
                return self.failAt(rules[i].line, 1, "no action for '|' rule", .{});
            }
            rules[i].action = rules[i + 1].action;
            rules[i].share_next = false;
        }
    }

    fn parseAll(self: *Parser) !Spec {
        var header = std.ArrayList(u8).init(self.alloc);
        var local = std.ArrayList(u8).init(self.alloc);
        var defs = std.ArrayList(Definition).init(self.alloc);
        var scs = std.ArrayList(StartCond).init(self.alloc);
        try scs.append(.{ .name = "INITIAL", .exclusive = false });
        var tables = TableSizes{};
        var yytext_array = false;

        try self.skipWsAndComments();
        while (self.peek()) |_| {
            try self.skipWsAndComments();
            const c = self.peek() orelse break;
            if (c == ' ' or c == '\t') {
                try self.copyLineAsC(&header);
                continue;
            }
            if (c == '%') {
                if (try self.parsePercent(&scs, &tables, &yytext_array, &header) == .section)
                    break;
                continue;
            }
            try self.parseDefinition(&defs);
        }

        var rules = std.ArrayList(Rule).init(self.alloc);
        var saw_rule = false;
        try self.skipWsAndComments();
        while (self.peek()) |_| {
            try self.skipWsAndComments();
            const c = self.peek() orelse break;
            if (c == '%' and self.peekAt(1) == '%') {
                _ = self.next();
                _ = self.next();
                self.skipToEol();
                if (self.peek() == '\n') _ = self.next();
                break;
            }
            if (c == ' ' or c == '\t') {
                if (!saw_rule) {
                    try self.copyLineAsC(&local);
                } else {
                    self.skipToEol();
                    if (self.peek() == '\n') _ = self.next();
                }
                continue;
            }
            if (self.starts("%{") and self.atLineStart()) {
                if (!saw_rule) {
                    try self.copyCBlock(&local);
                } else {
                    return self.fail("unexpected %{{ after rules", .{});
                }
                continue;
            }
            try self.parseRule(scs.items, &rules);
            saw_rule = true;
        }
        try self.resolveShares(rules.items);

        const user = std.mem.trim(u8, self.src[self.i..], " \t\r\n");
        return .{
            .header = try header.toOwnedSlice(),
            .local = try local.toOwnedSlice(),
            .user = user,
            .defs = try defs.toOwnedSlice(),
            .scs = try scs.toOwnedSlice(),
            .rules = try rules.toOwnedSlice(),
            .yytext_array = yytext_array,
            .tables = tables,
        };
    }
};

pub fn parse(alloc: std.mem.Allocator, d: *diag.Diag, filename: []const u8, src: []const u8) !Spec {
    d.file = filename;
    var p = Parser{
        .alloc = alloc,
        .d = d,
        .src = src,
    };
    return p.parseAll();
}

test "subject scanner parses" {
    const src =
        \\%%
        \\[0-9]+ printf("NUMBER: %s\n", yytext);
        \\"+" |
        \\"-" |
        \\"*" |
        \\"/" printf("OPERATOR: %s\n", yytext);
        \\"(" printf("OPEN PARENTHESIS\n");
        \\")" printf("CLOSED PARENTHESIS\n");
        \\"\n" printf("NEWLINE\n");
        \\[[:blank:]] // ignore whitespaces
        \\.   printf("Invalid character: %c\n", *yytext);
        \\
    ;
    var d = diag.Diag{};
    const spec = try parse(std.testing.allocator, &d, "scanner.l", src);
    defer {
        std.testing.allocator.free(spec.header);
        std.testing.allocator.free(spec.local);
        for (spec.defs) |def| std.testing.allocator.free(def.subst);
        std.testing.allocator.free(spec.defs);
        std.testing.allocator.free(spec.scs);
        for (spec.rules) |r| {
            if (r.scs.len > 0) std.testing.allocator.free(r.scs);
        }
        std.testing.allocator.free(spec.rules);
    }
    try std.testing.expectEqual(@as(usize, 10), spec.rules.len);
    try std.testing.expectEqualStrings("[0-9]+", spec.rules[0].pattern);
    try std.testing.expectEqualStrings("\"+\"", spec.rules[1].pattern);
    try std.testing.expectEqualStrings("\"/\"", spec.rules[4].pattern);
    try std.testing.expectEqualStrings("printf(\"OPERATOR: %s\\n\", yytext);", spec.rules[1].action);
    try std.testing.expectEqualStrings("printf(\"OPERATOR: %s\\n\", yytext);", spec.rules[4].action);
    try std.testing.expectEqualStrings("[[:blank:]]", spec.rules[8].pattern);
}
