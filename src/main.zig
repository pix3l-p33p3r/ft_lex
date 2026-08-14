const std = @import("std");
const diag = @import("diag.zig");
const lexfile = @import("lexfile.zig");
const nfa_mod = @import("nfa.zig");
const dfa_mod = @import("dfa.zig");
const emit = @import("emit.zig");
const emit_zig = @import("emit_zig.zig");

const Options = struct {
    t: bool = false,
    n: bool = false,
    v: bool = false,
    zig: bool = false,
    compress: bool = false,
    files: []const []const u8 = &.{},
};

fn usage(w: anytype) !void {
    try w.writeAll("Usage: ft_lex [-t] [-n|-v] [-z] [-C] [file...]\n");
}

fn parseOptions(alloc: std.mem.Allocator, args: []const []const u8) !Options {
    var opt = Options{};
    var files = std.ArrayList([]const u8).init(alloc);
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (a.len == 0) continue;
        if (std.mem.eql(u8, a, "-")) {
            try files.append(a);
            continue;
        }
        if (a[0] == '-' and a.len > 1) {
            for (a[1..]) |ch| {
                switch (ch) {
                    't' => opt.t = true,
                    'n' => opt.n = true,
                    'v' => opt.v = true,
                    'z' => opt.zig = true,
                    'C' => opt.compress = true,
                    else => {
                        const stderr = std.io.getStdErr().writer();
                        stderr.print("ft_lex: unrecognized option -- {c}\n", .{ch}) catch {};
                        usage(stderr) catch {};
                        return error.Usage;
                    },
                }
            }
        } else {
            try files.append(a);
            i += 1;
            while (i < args.len) : (i += 1) try files.append(args[i]);
            break;
        }
    }
    opt.files = try files.toOwnedSlice();
    return opt;
}

fn readSources(alloc: std.mem.Allocator, files: []const []const u8) !struct { name: []const u8, src: []u8 } {
    const stderr = std.io.getStdErr().writer();
    if (files.len == 0) {
        const src = std.io.getStdIn().readToEndAlloc(alloc, 16 * 1024 * 1024) catch {
            try stderr.writeAll("ft_lex: failed to read standard input\n");
            return error.Io;
        };
        return .{ .name = "stdin", .src = src };
    }

    var buf = std.ArrayList(u8).init(alloc);
    var name: []const u8 = files[0];
    for (files, 0..) |f, idx| {
        if (idx > 0) try buf.append('\n');
        if (std.mem.eql(u8, f, "-")) {
            std.io.getStdIn().reader().readAllArrayList(&buf, 16 * 1024 * 1024) catch {
                try stderr.writeAll("ft_lex: failed to read standard input\n");
                return error.Io;
            };
            continue;
        }
        const content = std.fs.cwd().readFileAlloc(alloc, f, 16 * 1024 * 1024) catch |e| {
            try stderr.print("ft_lex: cannot open {s}: {!}\n", .{ f, e });
            return error.Io;
        };
        defer alloc.free(content);
        try buf.appendSlice(content);
        if (idx == 0) name = f;
    }
    return .{ .name = name, .src = try buf.toOwnedSlice() };
}

pub fn main() u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();
    const alloc = arena.allocator();

    const stderr = std.io.getStdErr().writer();

    const args = std.process.argsAlloc(alloc) catch {
        stderr.writeAll("ft_lex: out of memory\n") catch {};
        return 1;
    };

    const opt = parseOptions(alloc, args) catch |e| switch (e) {
        error.Usage => return 1,
        error.OutOfMemory => {
            stderr.writeAll("ft_lex: out of memory\n") catch {};
            return 1;
        },
    };

    const input = readSources(alloc, opt.files) catch return 1;

    var d = diag.Diag{ .file = input.name };
    const spec = lexfile.parse(alloc, &d, input.name, input.src) catch |e| switch (e) {
        error.CompileFail => {
            d.write(stderr) catch {};
            return 1;
        },
        error.OutOfMemory => {
            stderr.writeAll("ft_lex: out of memory\n") catch {};
            return 1;
        },
    };

    const nfa = nfa_mod.build(alloc, &d, &spec) catch |e| switch (e) {
        error.CompileFail => {
            d.write(stderr) catch {};
            return 1;
        },
        error.OutOfMemory => {
            stderr.writeAll("ft_lex: out of memory\n") catch {};
            return 1;
        },
    };

    const dfa = dfa_mod.build(alloc, &d, &nfa, spec.tables.states) catch |e| switch (e) {
        error.CompileFail => {
            d.write(stderr) catch {};
            return 1;
        },
        error.OutOfMemory => {
            stderr.writeAll("ft_lex: out of memory\n") catch {};
            return 1;
        },
    };

    const out_src = if (opt.zig)
        emit_zig.generate(alloc, &spec, &dfa, opt.compress)
    else
        emit.generate(alloc, &spec, &dfa, opt.compress);
    const c_src = out_src catch {
        stderr.writeAll("ft_lex: out of memory\n") catch {};
        return 1;
    };

    if ((opt.v or spec.tables.specified) and !opt.n) {
        stderr.print(
            "ft_lex statistics:\n  {d} rules\n  {d} nfa states\n  {d} dfa states\n",
            .{ spec.rules.len, nfa.states.items.len, dfa.states.len },
        ) catch {};
    }

    if (opt.t) {
        std.io.getStdOut().writeAll(c_src) catch {
            stderr.writeAll("ft_lex: failed to write standard output\n") catch {};
            return 1;
        };
    } else {
        const out_name: []const u8 = if (opt.zig) "lex.yy.zig" else "lex.yy.c";
        const file = std.fs.cwd().createFile(out_name, .{}) catch {
            stderr.print("ft_lex: cannot create {s}\n", .{out_name}) catch {};
            return 1;
        };
        defer file.close();
        file.writeAll(c_src) catch {
            stderr.print("ft_lex: failed to write {s}\n", .{out_name}) catch {};
            return 1;
        };
    }
    return 0;
}
