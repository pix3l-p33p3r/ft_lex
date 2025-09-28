const std = @import("std");
const NFA = @import("../automata/nfa.zig").NFA;
const EPSILON = @import("../automata/nfa.zig").EPSILON;

pub const RegexError = error{
    UnexpectedCharacter,
    UnterminatedCharacterClass,
    EmptyCharacterClass,
    InvalidRange,
    UnmatchedParenthesis,
    InvalidEscape,
    EmptyExpression,
};

const TokenType = enum {
    Char,           // Single character
    CharClass,      // [...] character class
    Star,          // *
    Plus,          // +
    Question,      // ?
    Union,         // |
    LParen,        // (
    RParen,        // )
    Dot,           // . (any character)
    End,           // End of input
};

const Token = struct {
    type: TokenType,
    value: ?[]const u8,
};

const Lexer = struct {
    source: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(source: []const u8, allocator: std.mem.Allocator) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .allocator = allocator,
        };
    }

    fn peek(self: *Lexer) ?u8 {
        return if (self.pos < self.source.len) self.source[self.pos] else null;
    }

    fn advance(self: *Lexer) void {
        if (self.pos < self.source.len) self.pos += 1;
    }

    pub fn nextToken(self: *Lexer) !Token {
        const c = self.peek() orelse return Token{ .type = .End, .value = null };

        switch (c) {
            '*' => {
                self.advance();
                return Token{ .type = .Star, .value = null };
            },
            '+' => {
                self.advance();
                return Token{ .type = .Plus, .value = null };
            },
            '?' => {
                self.advance();
                return Token{ .type = .Question, .value = null };
            },
            '|' => {
                self.advance();
                return Token{ .type = .Union, .value = null };
            },
            '(' => {
                self.advance();
                return Token{ .type = .LParen, .value = null };
            },
            ')' => {
                self.advance();
                return Token{ .type = .RParen, .value = null };
            },
            '.' => {
                self.advance();
                return Token{ .type = .Dot, .value = null };
            },
            '[' => {
                self.advance();
                return self.readCharClass();
            },
            '\\' => {
                self.advance();
                const escaped = self.peek() orelse return error.InvalidEscape;
                self.advance();
                const value = try self.allocator.dupe(u8, &[_]u8{escaped});
                return Token{ .type = .Char, .value = value };
            },
            else => {
                self.advance();
                const value = try self.allocator.dupe(u8, &[_]u8{c});
                return Token{ .type = .Char, .value = value };
            },
        }
    }

    fn readCharClass(self: *Lexer) !Token {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        var negate = false;
        if (self.peek()) |c| {
            if (c == '^') {
                negate = true;
                self.advance();
            }
        }

        while (self.peek()) |c| {
            if (c == ']') {
                self.advance();
                if (buffer.items.len == 0) return error.EmptyCharacterClass;
                
                var class = try self.allocator.alloc(u8, buffer.items.len + 1);
                class[0] = if (negate) '^' else buffer.items[0];
                @memcpy(class[1..], if (negate) buffer.items[0..] else buffer.items[1..]);
                
                return Token{ .type = .CharClass, .value = class };
            }

            if (c == '\\') {
                self.advance();
                const escaped = self.peek() orelse return error.InvalidEscape;
                try buffer.append(escaped);
            } else {
                try buffer.append(c);
            }
            self.advance();
        }

        return error.UnterminatedCharacterClass;
    }
};

pub fn parseRegex(allocator: std.mem.Allocator, pattern: []const u8) !NFA {
    var lexer = Lexer.init(pattern, allocator);
    var nfa_stack = std.ArrayList(*NFA).init(allocator);
    defer nfa_stack.deinit();

    var current_nfa: ?*NFA = null;

    while (true) {
        const token = try lexer.nextToken();
        switch (token.type) {
            .End => break,
            .Char => {
                var new_nfa = try allocator.create(NFA);
                new_nfa.* = try NFA.forChar(allocator, token.value.?[0]);

                if (current_nfa) |nfa| {
                    try nfa.concat(new_nfa);
                    new_nfa.deinit();
                    allocator.destroy(new_nfa);
                } else {
                    current_nfa = new_nfa;
                }
            },
            .CharClass => {
                var parser = CharClassParser.init(token.value.?);
                var charset = try parser.parse();

                // Create an NFA that matches any character in the set
                var new_nfa = try allocator.create(NFA);
                new_nfa.* = try NFA.init(allocator);
                const start = try new_nfa.addState();
                const end = try new_nfa.addState();
                new_nfa.start = start;
                new_nfa.states.items[end].is_accepting = true;

                // Add transitions for each character in the set
                var i: u16 = 0;
                while (i < 256) : (i += 1) {
                    if (charset.contains(@intCast(i))) {
                        try new_nfa.addTransition(start, i, end);
                    }
                }

                if (current_nfa) |nfa| {
                    try nfa.concat(new_nfa);
                    new_nfa.deinit();
                    allocator.destroy(new_nfa);
                } else {
                    current_nfa = new_nfa;
                }
            },
            .Star => {
                if (current_nfa) |nfa| {
                    try nfa.star();
                }
            },
            .Plus => {
                if (current_nfa) |nfa| {
                    try nfa.plus();
                }
            },
            .Question => {
                if (current_nfa) |nfa| {
                    try nfa.optional();
                }
            },
            .Union => {
                if (current_nfa) |nfa| {
                    try nfa_stack.append(nfa);
                }
                current_nfa = null;
            },
            .LParen => {
                if (current_nfa) |nfa| {
                    try nfa_stack.append(nfa);
                }
                current_nfa = null;
            },
            .RParen => {
                if (nfa_stack.items.len == 0) {
                    return error.UnmatchedParenthesis;
                }
                var last_nfa = nfa_stack.pop();
                if (current_nfa) |nfa| {
                    try last_nfa.concat(nfa);
                    nfa.deinit();
                    allocator.destroy(nfa);
                }
                current_nfa = last_nfa;
            },
            .Dot => {
                // TODO: Implement dot (match any character)
                var new_nfa = try allocator.create(NFA);
                new_nfa.* = try NFA.forChar(allocator, '.');

                if (current_nfa) |nfa| {
                    try nfa.concat(new_nfa);
                    new_nfa.deinit();
                    allocator.destroy(new_nfa);
                } else {
                    current_nfa = new_nfa;
                }
            },
        }
    }

    // Handle any remaining NFAs on the stack (for unions)
    while (nfa_stack.items.len > 0) {
        var last_nfa = nfa_stack.pop();
        if (current_nfa) |nfa| {
            try last_nfa.union(nfa);
            nfa.deinit();
            allocator.destroy(nfa);
        }
        current_nfa = last_nfa;
    }

    if (current_nfa) |nfa| {
        return nfa.*;
    } else {
        return error.EmptyExpression;
    }
}
