const std = @import("std");

pub const TokenType = enum {
    Name,           // Identifier
    Definition,     // {name}
    String,         /    pub fn readString(self: *Lexer)     pub fn readDefinition(self: *Lexer) !?Token {
        const start = self.pos;
        self.advance(1); // Skip opening brace

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '}') {
                self.advance(1);
                return Token{
                    .type = .Definition,
                    .value = self.source[start..self.pos],
                    .line = self.line,
                    .column = self.column - (self.pos - start),
                };
            }
            self.advance(1);
        }
        return error.UnterminatedAction;const start = self.pos;
        self.advance(1); // Skip opening quote

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '"' and self.source[self.pos - 1] != '\\') {
                self.advance(1);
                return Token{
                    .type = .String,
                    .value = self.source[start..self.pos],
                    .line = self.line,
                    .column = self.column - (self.pos - start),
                };
            }
            self.advance(1);
        }
        return error.UnterminatedString;gex,         // Regular expression
    Action,        // C code block
    Pipe,          // |
    Newline,       // \n
    Section,       // %%
    Whitespace,    // space, tab
    Comment,       // // or /* */
    Eof,           // End of file
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    line: usize,
    column: usize,
};

pub const LexError = error{
    InvalidCharacter,
    UnterminatedString,
    UnterminatedAction,
    UnterminatedComment,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    column: usize,
    allocator: std.mem.Allocator,
    inDefinitionSection: bool = true,

    pub fn init(source: []const u8, allocator: std.mem.Allocator) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
            .allocator = allocator,
            .inDefinitionSection = true,
        };
    }

    pub fn nextToken(self: *Lexer) !?Token {
        self.skipWhitespace();

        if (self.pos >= self.source.len) {
            return null; // EOF
        }

        const c = self.source[self.pos];
        switch (c) {
            '%' => {
                if (self.peek(1) == '%') {
                    const token = Token{
                        .type = .Section,
                        .value = self.source[self.pos..self.pos+2],
                        .line = self.line,
                        .column = self.column,
                    };
                    self.advance(2);
                    return token;
                }
            },
            '"' => return (try self.readString()) orelse null,
            '{' => {
                if (self.inDefinitionSection) {
                    return (try self.readDefinition()) orelse null;
                } else {
                    return (try self.readAction()) orelse null;
                }
            },
            '/' => {
                if (self.peek(1) == '/') return self.readLineComment();
                if (self.peek(1) == '*') return self.readBlockComment();
            },
            '|' => {
                const token = Token{
                    .type = .Pipe,
                    .value = self.source[self.pos..self.pos+1],
                    .line = self.line,
                    .column = self.column,
                };
                self.advance(1);
                return token;
            },
            '\n' => {
                const token = Token{
                    .type = .Newline,
                    .value = "\n",
                    .line = self.line,
                    .column = self.column,
                };
                self.advance(1);
                self.line += 1;
                self.column = 1;
                return token;
            },
            else => {
                if (isNameStart(c)) {
                    return (try self.readName()) orelse null;
                } else {
                    return (try self.readRegex()) orelse null;
                }
            },
        }
        return error.InvalidCharacter;
    }

    fn peek(self: *Lexer, offset: usize) u8 {
        if (self.pos + offset >= self.source.len) return 0;
        return self.source[self.pos + offset];
    }

    fn advance(self: *Lexer, count: usize) void {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (self.pos < self.source.len) {
                if (self.source[self.pos] == '\n') {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }
                self.pos += 1;
            }
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c != ' ' and c != '\t' and c != '\r') break;
            self.advance(1);
        }
    }

    fn readString(self: *Lexer) !Token {
        const start = self.pos;
        self.advance(1); // Skip opening quote

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '"' and self.source[self.pos - 1] != '\\') {
                self.advance(1);
                return Token{
                    .type = .String,
                    .value = self.source[start..self.pos],
                    .line = self.line,
                    .column = self.column - (self.pos - start),
                };
            }
            self.advance(1);
        }
        return error.UnterminatedString;
    }

    fn readDefinition(self: *Lexer) !Token {
        const start = self.pos;
        self.advance(1); // Skip opening brace

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '}') {
                self.advance(1);
                return Token{
                    .type = .Definition,
                    .value = self.source[start..self.pos],
                    .line = self.line,
                    .column = self.column - (self.pos - start),
                };
            }
            self.advance(1);
        }
        return error.UnterminatedAction;
    }

    fn readAction(self: *Lexer) !Token {
        const start = self.pos;
        self.advance(1); // Skip opening brace
        var brace_count: usize = 1;

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '{') {
                brace_count += 1;
            } else if (c == '}') {
                brace_count -= 1;
                if (brace_count == 0) {
                    self.advance(1);
                    return Token{
                        .type = .Action,
                        .value = self.source[start..self.pos],
                        .line = self.line,
                        .column = self.column - (self.pos - start),
                    };
                }
            }
            self.advance(1);
        }
        return error.UnterminatedAction;
    }

    fn readRegex(self: *Lexer) !?Token {
        const start = self.pos;
        var in_char_class = false;

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '[') {
                in_char_class = true;
            } else if (c == ']' and in_char_class) {
                in_char_class = false;
            } else if (!in_char_class) {
                if (c == ' ' or c == '\t' or c == '\n' or c == '{') {
                    return Token{
                        .type = .Regex,
                        .value = self.source[start..self.pos],
                        .line = self.line,
                        .column = self.column - (self.pos - start),
                    };
                }
            }
            self.advance(1);
        }
        
        // End of file reached
        if (self.pos > start) {
            return Token{
                .type = .Regex,
                .value = self.source[start..self.pos],
                .line = self.line,
                .column = self.column - (self.pos - start),
            };
        }
        return null;
    }
};

fn isNameStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
           (c >= 'A' and c <= 'Z') or
           c == '_';
}
