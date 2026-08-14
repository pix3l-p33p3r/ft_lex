const std = @import("std");
const diag = @import("diag.zig");
const lexfile = @import("lexfile.zig");

pub const Class = struct {
    negate: bool = false,
    bits: std.StaticBitSet(256) = std.StaticBitSet(256).initEmpty(),

    pub fn has(self: Class, c: u8) bool {
        const in = self.bits.isSet(c);
        return if (self.negate) !in else in;
    }

    pub fn set(self: *Class, c: u8) void {
        self.bits.set(c);
    }

    pub fn setRange(self: *Class, a: u8, b: u8) void {
        var i: usize = a;
        while (i <= b) : (i += 1) self.bits.set(i);
    }
};

pub const NodeKind = enum {
    empty,
    byte,
    class,
    concat,
    alt,
    star,
    plus,
    opt,
};

pub const Node = struct {
    kind: NodeKind,
    c: u8 = 0,
    class: ?*Class = null,
    left: ?*Node = null,
    right: ?*Node = null,
};

const Parser = struct {
    alloc: std.mem.Allocator,
    d: *diag.Diag,
    defs: []const lexfile.Definition,
    src: []const u8,
    i: usize = 0,
    line: u32,
    expanding: u32 = 0,

    fn fail(self: *Parser, comptime fmt: []const u8, args: anytype) diag.Fail {
        self.d.set(self.line, 1, fmt, args);
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
        return c;
    }

    fn node(self: *Parser, kind: NodeKind) !*Node {
        const n = try self.alloc.create(Node);
        n.* = .{ .kind = kind };
        return n;
    }

    fn byteNode(self: *Parser, c: u8) !*Node {
        const n = try self.node(.byte);
        n.c = c;
        return n;
    }

    fn classNode(self: *Parser, cl: Class) !*Node {
        const heap = try self.alloc.create(Class);
        heap.* = cl;
        const n = try self.node(.class);
        n.class = heap;
        return n;
    }

    fn bin(self: *Parser, kind: NodeKind, l: *Node, r: *Node) !*Node {
        const n = try self.node(kind);
        n.left = l;
        n.right = r;
        return n;
    }

    fn unary(self: *Parser, kind: NodeKind, inner: *Node) !*Node {
        const n = try self.node(kind);
        n.left = inner;
        return n;
    }

    fn parseEscape(self: *Parser) diag.Fail!u8 {
        const c = self.next() orelse return self.fail("unexpected end of file", .{});
        return switch (c) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            'a' => 0x07,
            'b' => 0x08,
            'f' => 0x0c,
            'v' => 0x0b,
            '\\' => '\\',
            '"' => '"',
            '\'' => '\'',
            '/' => '/',
            'x', 'X' => blk: {
                var val: u32 = 0;
                var n: u32 = 0;
                while (self.peek()) |h| {
                    const d = std.fmt.charToDigit(h, 16) catch break;
                    val = (val << 4) + d;
                    n += 1;
                    _ = self.next();
                    if (n >= 2) break;
                }
                if (n == 0) return self.fail("bad hexadecimal escape", .{});
                if (val == 0) return self.fail("NUL escape is undefined", .{});
                break :blk @truncate(val);
            },
            '0'...'7' => blk: {
                var val: u32 = c - '0';
                var n: u32 = 1;
                while (n < 3) : (n += 1) {
                    const d = self.peek() orelse break;
                    if (d < '0' or d > '7') break;
                    val = (val << 3) + (d - '0');
                    _ = self.next();
                }
                if (val == 0) return self.fail("NUL escape is undefined", .{});
                break :blk @truncate(val);
            },
            else => c,
        };
    }

    fn posixClass(self: *Parser, name: []const u8, cl: *Class) !void {
        const pred: *const fn (u8) bool = if (std.mem.eql(u8, name, "alnum"))
            &std.ascii.isAlphanumeric
        else if (std.mem.eql(u8, name, "alpha"))
            &std.ascii.isAlphabetic
        else if (std.mem.eql(u8, name, "blank"))
            &isBlank
        else if (std.mem.eql(u8, name, "cntrl"))
            &std.ascii.isControl
        else if (std.mem.eql(u8, name, "digit"))
            &std.ascii.isDigit
        else if (std.mem.eql(u8, name, "graph"))
            &isGraph
        else if (std.mem.eql(u8, name, "lower"))
            &std.ascii.isLower
        else if (std.mem.eql(u8, name, "print"))
            &isPrint
        else if (std.mem.eql(u8, name, "punct"))
            &isPunct
        else if (std.mem.eql(u8, name, "space"))
            &std.ascii.isWhitespace
        else if (std.mem.eql(u8, name, "upper"))
            &std.ascii.isUpper
        else if (std.mem.eql(u8, name, "xdigit"))
            &isXdigit
        else
            return self.fail("invalid POSIX class '[{s}:]'", .{name});

        var i: u32 = 0;
        while (i < 256) : (i += 1) {
            if (pred(@truncate(i))) cl.set(@truncate(i));
        }
    }

    fn parseClass(self: *Parser) diag.Fail!*Node {
        // caller consumed '['
        var cl = Class{};
        if (self.peek() == '^') {
            cl.negate = true;
            _ = self.next();
        }
        var first = true;
        while (self.peek()) |c0| {
            if (c0 == ']' and !first) {
                _ = self.next();
                return self.classNode(cl);
            }
            first = false;

            if (c0 == '[' and self.peekAt(1) == ':') {
                _ = self.next();
                _ = self.next();
                const ns = self.i;
                while (self.peek()) |c| {
                    if (c == ':') break;
                    if (!std.ascii.isAlphabetic(c)) return self.fail("invalid POSIX class", .{});
                    _ = self.next();
                }
                const name = self.src[ns..self.i];
                if (!self.starts(":]")) return self.fail("malformed bracket expression", .{});
                _ = self.next();
                _ = self.next();
                try self.posixClass(name, &cl);
                continue;
            }

            const a = if (c0 == '\\') blk: {
                _ = self.next();
                break :blk try self.parseEscape();
            } else blk: {
                _ = self.next();
                break :blk c0;
            };

            if (self.peek() == '-' and self.peekAt(1) != null and self.peekAt(1) != ']') {
                _ = self.next();
                const b0 = self.peek() orelse return self.fail("malformed bracket expression", .{});
                const b = if (b0 == '\\') blk: {
                    _ = self.next();
                    break :blk try self.parseEscape();
                } else blk: {
                    _ = self.next();
                    break :blk b0;
                };
                if (b < a) return self.fail("bracket expression out of order", .{});
                cl.setRange(a, b);
            } else {
                cl.set(a);
            }
        }
        return self.fail("malformed bracket expression", .{});
    }

    fn starts(self: *const Parser, s: []const u8) bool {
        if (self.i + s.len > self.src.len) return false;
        return std.mem.eql(u8, self.src[self.i .. self.i + s.len], s);
    }

    fn parseQuoted(self: *Parser) diag.Fail!*Node {
        // caller consumed '"'
        var acc: ?*Node = null;
        while (self.peek()) |c| {
            if (c == '"') {
                _ = self.next();
                return acc orelse try self.node(.empty);
            }
            const b = if (c == '\\') blk: {
                _ = self.next();
                break :blk try self.parseEscape();
            } else blk: {
                _ = self.next();
                break :blk c;
            };
            const n = try self.byteNode(b);
            acc = if (acc) |left| try self.bin(.concat, left, n) else n;
        }
        return self.fail("unbalanced quotes", .{});
    }

    fn parseBrace(self: *Parser, inner: ?*Node) diag.Fail!*Node {
        // caller consumed '{'
        const start = self.i;
        if (self.peek()) |c| {
            if (std.ascii.isDigit(c) and inner != null) {
                const min = try self.takeInt();
                var max: u32 = min;
                if (self.peek() == ',') {
                    _ = self.next();
                    if (self.peek()) |d| {
                        if (std.ascii.isDigit(d)) {
                            max = try self.takeInt();
                            if (max < min) return self.fail("bad interval expression", .{});
                        } else {
                            max = std.math.maxInt(u32);
                        }
                    } else {
                        max = std.math.maxInt(u32);
                    }
                }
                if (self.peek() != '}') return self.fail("unexpected token '{c}'", .{self.peek() orelse '?'});
                _ = self.next();
                return self.applyRepeat(inner.?, min, max);
            }
        }

        while (self.peek()) |c| {
            if (c == '}') break;
            if (!(std.ascii.isAlphanumeric(c) or c == '_')) {
                return self.fail("unexpected token '{c}'", .{c});
            }
            _ = self.next();
        }
        if (self.peek() != '}') return self.fail("unexpected token '{c}'", .{self.peek() orelse '?'});
        const name = self.src[start..self.i];
        _ = self.next();
        if (name.len == 0) return self.fail("empty definition name", .{});

        const subst = blk: {
            for (self.defs) |def| {
                if (std.mem.eql(u8, def.name, name)) break :blk def.subst;
            }
            return self.fail("no such definition '{s}'", .{name});
        };

        if (self.expanding > 32) return self.fail("recursive definition not allowed", .{});
        var nested = Parser{
            .alloc = self.alloc,
            .d = self.d,
            .defs = self.defs,
            .src = subst,
            .line = self.line,
            .expanding = self.expanding + 1,
        };
        return nested.parseAlt();
    }

    fn takeInt(self: *Parser) !u32 {
        const start = self.i;
        while (self.peek()) |c| {
            if (!std.ascii.isDigit(c)) break;
            _ = self.next();
        }
        if (start == self.i) return self.fail("expected number", .{});
        return std.fmt.parseInt(u32, self.src[start..self.i], 10) catch {
            return self.fail("bad number", .{});
        };
    }

    fn applyRepeat(self: *Parser, inner: *Node, min: u32, max: u32) diag.Fail!*Node {
        if (min > 10000 or (max != std.math.maxInt(u32) and max > 10000)) {
            return self.fail("interval expression too large", .{});
        }
        if (min == 0 and max == 0) return try self.node(.empty);
        var acc: ?*Node = null;
        var i: u32 = 0;
        while (i < min) : (i += 1) {
            acc = if (acc) |l| try self.bin(.concat, l, inner) else inner;
        }
        if (max == std.math.maxInt(u32)) {
            const star = try self.unary(.star, inner);
            return if (acc) |l| try self.bin(.concat, l, star) else star;
        }
        var extra = max - min;
        var opt_chain: ?*Node = null;
        while (extra > 0) : (extra -= 1) {
            const o = try self.unary(.opt, inner);
            opt_chain = if (opt_chain) |l| try self.bin(.concat, l, o) else o;
        }
        if (opt_chain) |o| {
            return if (acc) |l| try self.bin(.concat, l, o) else o;
        }
        return acc orelse try self.node(.empty);
    }

    fn parseAtom(self: *Parser) diag.Fail!*Node {
        const c = self.peek() orelse return self.fail("unexpected end of file", .{});
        switch (c) {
            '.' => {
                _ = self.next();
                var cl = Class{};
                cl.setRange(0, 255);
                cl.bits.unset('\n');
                return self.classNode(cl);
            },
            '[' => {
                _ = self.next();
                return self.parseClass();
            },
            '"' => {
                _ = self.next();
                return self.parseQuoted();
            },
            '(' => {
                _ = self.next();
                const inner = try self.parseAlt();
                if (self.peek() != ')') {
                    if (self.peek() == null) return self.fail("unbalanced parenthesis", .{});
                    return self.fail("unexpected token '{c}'", .{self.peek().?});
                }
                _ = self.next();
                return inner;
            },
            ')' => return self.fail("unexpected token ')'", .{}),
            ']' => return self.fail("unexpected token ']'", .{}),
            '*' => return self.fail("unexpected token '*'", .{}),
            '+' => return self.fail("unexpected token '+'", .{}),
            '?' => return self.fail("unexpected token '?'", .{}),
            '|' => return self.fail("unexpected token '|'", .{}),
            '{' => {
                _ = self.next();
                return self.parseBrace(null);
            },
            '\\' => {
                _ = self.next();
                return self.byteNode(try self.parseEscape());
            },
            else => {
                _ = self.next();
                return self.byteNode(c);
            },
        }
    }

    fn parseDup(self: *Parser) diag.Fail!*Node {
        var n = try self.parseAtom();
        while (self.peek()) |c| {
            switch (c) {
                '*' => {
                    _ = self.next();
                    n = try self.unary(.star, n);
                },
                '+' => {
                    _ = self.next();
                    n = try self.unary(.plus, n);
                },
                '?' => {
                    _ = self.next();
                    n = try self.unary(.opt, n);
                },
                '{' => {
                    const save = self.i;
                    _ = self.next();
                    if (self.peek()) |d| {
                        if (std.ascii.isDigit(d)) {
                            n = try self.parseBrace(n);
                            continue;
                        }
                    }
                    self.i = save;
                    break;
                },
                else => break,
            }
        }
        return n;
    }

    fn parseConcat(self: *Parser) diag.Fail!*Node {
        var n = try self.parseDup();
        while (self.peek()) |c| {
            if (c == '|' or c == ')') break;
            const r = try self.parseDup();
            n = try self.bin(.concat, n, r);
        }
        return n;
    }

    fn parseAlt(self: *Parser) diag.Fail!*Node {
        var n = try self.parseConcat();
        while (self.peek() == '|') {
            _ = self.next();
            const r = try self.parseConcat();
            n = try self.bin(.alt, n, r);
        }
        return n;
    }
};

fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn isGraph(c: u8) bool {
    return c >= 0x21 and c <= 0x7e;
}

fn isPrint(c: u8) bool {
    return c >= 0x20 and c <= 0x7e;
}

fn isPunct(c: u8) bool {
    return isGraph(c) and !std.ascii.isAlphanumeric(c);
}

fn isXdigit(c: u8) bool {
    return std.ascii.isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

pub fn parseEre(
    alloc: std.mem.Allocator,
    d: *diag.Diag,
    defs: []const lexfile.Definition,
    ere: []const u8,
    line: u32,
) !*Node {
    var p = Parser{
        .alloc = alloc,
        .d = d,
        .defs = defs,
        .src = ere,
        .line = line,
    };
    const n = try p.parseAlt();
    if (p.peek()) |c| {
        return p.fail("unexpected token '{c}'", .{c});
    }
    return n;
}

test "parse digit class" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diag{};
    const n = try parseEre(arena.allocator(), &d, &.{}, "[0-9]+", 1);
    try std.testing.expect(n.kind == .plus);
    try std.testing.expect(n.left.?.kind == .class);
    try std.testing.expect(n.left.?.class.?.has('5'));
    try std.testing.expect(!n.left.?.class.?.has('a'));
}

test "bad regex reports token" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diag{};
    try std.testing.expectError(error.CompileFail, parseEre(arena.allocator(), &d, &.{}, "[0-9]+)", 12));
    try std.testing.expectEqual(@as(u32, 12), d.line);
    try std.testing.expectEqualStrings("unexpected token ')'", d.msg());
}
