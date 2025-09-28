const std = @import("std");
const DFA = @import("../automata/dfa.zig").DFA;
const parser = @import("../parser/parser.zig");

const TransitionTable = struct {
    table: [][]?usize,
    symbols: []u21,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, dfa: *const DFA) !TransitionTable {
        var symbols = std.ArrayList(u21).init(allocator);
        defer symbols.deinit();

        // Collect all input symbols
        for (dfa.states.items) |state| {
            var it = state.transitions.keyIterator();
            while (it.next()) |symbol| {
                for (symbols.items) |s| {
                    if (s == symbol.*) break;
                } else {
                    try symbols.append(symbol.*);
                }
            }
        }

        // Create and initialize the transition table
        var table = try allocator.alloc([]?usize, dfa.states.items.len);
        for (table) |*row| {
            row.* = try allocator.alloc(?usize, symbols.items.len);
            @memset(row.*, null);
        }

        // Fill the transition table
        for (dfa.states.items, 0..) |state, from| {
            var it = state.transitions.iterator();
            while (it.next()) |entry| {
                const symbol = entry.key_ptr.*;
                const to = entry.value_ptr.*;
                
                for (symbols.items, 0..) |s, i| {
                    if (s == symbol) {
                        table[from][i] = to;
                        break;
                    }
                }
            }
        }

        return TransitionTable{
            .table = table,
            .symbols = try symbols.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TransitionTable) void {
        for (self.table) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.table);
        self.allocator.free(self.symbols);
    }
};

pub fn generateCode(allocator: std.mem.Allocator, lexfile: parser.LexFile, dfa: *const DFA, output_path: []const u8) !void {
    var file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    const writer = file.writer();

    // Initialize transition table
    var transitions = try TransitionTable.init(allocator, dfa);
    defer transitions.deinit();

    // Generate headers and includes
    try writer.writeAll(
        \\#include <stdio.h>
        \\#include <string.h>
        \\#include <stdlib.h>
        \\#include "libl.h"
        \\
        \\/* Transition table and state information */
        \\static const int yy_transitions[][256] = {
    );

    // Generate transition table
    for (transitions.table, 0..) |row, i| {
        try writer.writeAll("    {");
        for (transitions.symbols, 0..) |symbol, j| {
            if (row[j]) |target| {
                try writer.print("{d}", .{target});
            } else {
                try writer.writeAll("-1");
            }
            if (j < transitions.symbols.len - 1) {
                try writer.writeAll(", ");
            }
        }
        try writer.writeAll("},\n");
    }
    try writer.writeAll("};\n\n");

    // Generate symbol table
    try writer.writeAll("static const int yy_symbols[] = {\n    ");
    for (transitions.symbols, 0..) |symbol, i| {
        try writer.print("{d}", .{symbol});
        if (i < transitions.symbols.len - 1) {
            try writer.writeAll(", ");
        }
    }
    try writer.writeAll("\n};\n\n");

    // Generate accepting states
    try writer.writeAll("static const int yy_accepting[] = {\n    ");
    for (dfa.states.items, 0..) |state, i| {
        try writer.print("{d}", .{@intFromBool(state.is_accepting)});
        if (i < dfa.states.items.len - 1) {
            try writer.writeAll(", ");
        }
    }
    try writer.writeAll("\n};\n\n");

    // Generate buffer management code
    try writer.writeAll(
        \\/* Buffer management */
        \\static char yy_buffer[YY_BUF_SIZE];
        \\static int yy_buffer_start = 0;
        \\static int yy_buffer_end = 0;
        \\static int yy_buffer_pos = 0;
        \\
        \\static int yy_get_next_char(void) {
        \\    if (yy_buffer_pos >= yy_buffer_end) {
        \\        yy_buffer_end = fread(yy_buffer, 1, YY_BUF_SIZE, yyin);
        \\        yy_buffer_pos = 0;
        \\        yy_buffer_start = 0;
        \\        if (yy_buffer_end == 0) return EOF;
        \\    }
        \\    return yy_buffer[yy_buffer_pos++];
        \\}
        \\
        \\int yylex(void) {
        \\    if (yyin == NULL) yyin = stdin;
        \\    if (yyout == NULL) yyout = stdout;
        \\
        \\    int current_state = 0;
        \\    int last_accepting_state = -1;
        \\    int last_accepting_pos = -1;
        \\    int c;
        \\
        \\    while ((c = yy_get_next_char()) != EOF) {
        \\        int next_state = -1;
        \\
        \\        // Check transition for the current character
        \\        for (int i = 0; i < sizeof(yy_symbols)/sizeof(int); i++) {
        \\            if (yy_symbols[i] == c) {
        \\                next_state = yy_transitions[current_state][i];
        \\                break;
        \\            }
        \\        }
        \\
    );

    // Generate state transition code
    try writer.writeAll(
        \\        if (next_state == -1) {
        \\            if (last_accepting_state == -1) {
        \\                fprintf(stderr, "Invalid token\n");
        \\                return -1;
        \\            }
        \\            // Rewind to last accepting state
        \\            fseek(yyin, last_accepting_pos - yy_buffer_end + yy_buffer_start, SEEK_CUR);
        \\            yy_buffer_pos = last_accepting_pos;
        \\            
        \\            // Set up yytext
        \\            yyleng = last_accepting_pos - yy_buffer_start;
        \\            yytext = malloc(yyleng + 1);
        \\            memcpy(yytext, yy_buffer + yy_buffer_start, yyleng);
        \\            yytext[yyleng] = '\0';
        \\
        \\            // Execute action based on accepting state
        \\            switch (last_accepting_state) {
    );

    // Generate actions for each accepting state
    for (lexfile.rules.items, 0..) |rule, i| {
        try writer.print(
            \\                case {d}: {{
            \\                    {s}
            \\                    break;
            \\                }}
            \\
        , .{ i, rule.action });
    }

    // Close the switch and yylex function
    try writer.writeAll(
        \\            }
        \\            
        \\            free(yytext);
        \\            return 0;
        \\        }
        \\
        \\        if (yy_accepting[next_state]) {
        \\            last_accepting_state = next_state;
        \\            last_accepting_pos = yy_buffer_pos;
        \\        }
        \\
        \\        current_state = next_state;
        \\    }
        \\
        \\    return 0;
        \\}
        \\
        \\int yywrap(void) {
        \\    return 1;
        \\}
        \\
    );

    // Add user code section
    if (lexfile.user_code.len > 0) {
        try writer.writeAll("\n/* User code section */\n");
        try writer.writeAll(lexfile.user_code);
    }
}
