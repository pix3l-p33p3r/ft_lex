const std = @import("std");

// External variables
pub var yyin: *std.fs.File = undefined;
pub var yyout: *std.fs.File = undefined;
pub var yytext: []u8 = undefined;
pub var yyleng: usize = 0;
pub var yylineno: usize = 1;

// Internal variables
var yy_more_flag: bool = false;
var yy_more_len: usize = 0;

pub export fn yymore() void {
    yy_more_flag = true;
}

pub export fn yyless(n: c_int) void {
    if (n < 0 or n > @as(c_int, @intCast(yyleng))) return;
    // Push back characters beyond n
    const pushback = yyleng - @as(usize, @intCast(n));
    if (pushback > 0) {
        // TODO: Implement proper buffer management for pushback
    }
    yyleng = @as(usize, @intCast(n));
}

pub export fn yyrestart(input_file: *std.fs.File) void {
    yyin = input_file;
    yylineno = 1;
    // Reset internal buffers
    yy_more_flag = false;
    yy_more_len = 0;
}

pub export fn yywrap() c_int {
    return 1;
}
