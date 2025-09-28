const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const TokenType = @import("lexer.zig").TokenType;

pub const Section = enum {
    Definitions,
    Rules,
    UserCode,
};

pub const LexFile = struct {
    definitions: std.StringHashMap([]const u8),
    rules: std.ArrayList(Rule),
    user_code: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LexFile {
        return .{
            .definitions = std.StringHashMap([]const u8).init(allocator),
            .rules = std.ArrayList(Rule).init(allocator),
            .user_code = "",
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LexFile) void {
        var it = self.definitions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.definitions.deinit();
        
        for (self.rules.items) |*rule| {
            rule.deinit(self.allocator);
        }
        self.rules.deinit();
        self.allocator.free(self.user_code);
    }
};

pub const Rule = struct {
    pattern: []const u8,
    action: []const u8,

    pub fn deinit(self: *Rule, allocator: std.mem.Allocator) void {
        allocator.free(self.pattern);
        allocator.free(self.action);
    }
};

pub const ParseError = error{
    InvalidSyntax,
    UnexpectedToken,
    MissingSectionDelimiter,
    DuplicateDefinition,
};

pub fn parseLexFile(allocator: std.mem.Allocator, filename: []const u8) !LexFile {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);

    var lexer = Lexer.init(source, allocator);
    var lexfile = LexFile.init(allocator);
    errdefer lexfile.deinit();

    var current_section = Section.Definitions;
    var current_pattern: ?[]const u8 = null;

    while (try lexer.nextToken()) |token| {
        switch (token.type) {
            .Section => {
                switch (current_section) {
                    .Definitions => current_section = .Rules,
                    .Rules => current_section = .UserCode,
                    .UserCode => return error.UnexpectedToken,
                }
            },
            .Definition => {
                if (current_section != .Definitions) {
                    return error.UnexpectedToken;
                }
                try parseDefinition(&lexfile, token);
            },
            .Regex => {
                if (current_section != .Rules) {
                    return error.UnexpectedToken;
                }
                current_pattern = try allocator.dupe(u8, token.value);
            },
            .Action => {
                if (current_pattern == null) {
                    return error.InvalidSyntax;
                }
                try lexfile.rules.append(Rule{
                    .pattern = current_pattern.?,
                    .action = try allocator.dupe(u8, token.value),
                });
                current_pattern = null;
            },
            else => {},
        }
    }

    if (current_section != .UserCode) {
        return error.MissingSectionDelimiter;
    }

    return lexfile;
}

fn parseDefinition(lexfile: *LexFile, token: Token) !void {
    const definition = token.value;
    // Extract name and value from definition
    const equals_pos = std.mem.indexOf(u8, definition, "=") orelse return error.InvalidSyntax;
    const name = std.mem.trim(u8, definition[0..equals_pos], " \t");
    const value = std.mem.trim(u8, definition[equals_pos + 1..], " \t");

    try lexfile.definitions.put(
        try lexfile.allocator.dupe(u8, name),
        try lexfile.allocator.dupe(u8, value)
    );
}

const Parser = struct {
    lexer: *Lexer,
    allocator: std.mem.Allocator,

    pub fn init(lexer: *Lexer, allocator: std.mem.Allocator) Parser {
        return .{
            .lexer = lexer,
            .allocator = allocator,
        };
    }

    fn handleSectionMarker(self: *Parser) !void {
        if (self.lexer.peekToken()) |token| {
            if (token.type == .Section) {
                _ = try self.lexer.nextToken();
                self.lexer.inDefinitionSection = false;
            }
        }
    }
};
