const std = @import("std");

/// Compile-time diagnostic. Printed as `file:line message`.
pub const Diag = struct {
    file: []const u8 = "stdin",
    line: u32 = 1,
    col: u32 = 1,
    msg_buf: [256]u8 = undefined,
    msg_len: usize = 0,
    set_flag: bool = false,

    pub fn set(self: *Diag, line: u32, col: u32, comptime fmt: []const u8, args: anytype) void {
        self.line = line;
        self.col = col;
        self.set_flag = true;
        const written = std.fmt.bufPrint(&self.msg_buf, fmt, args) catch blk: {
            break :blk self.msg_buf[0..0];
        };
        self.msg_len = written.len;
        if (self.msg_len == 0) {
            const fallback = "invalid input";
            @memcpy(self.msg_buf[0..fallback.len], fallback);
            self.msg_len = fallback.len;
        }
    }

    pub fn msg(self: *const Diag) []const u8 {
        return self.msg_buf[0..self.msg_len];
    }

    pub fn write(self: *const Diag, w: anytype) !void {
        const name = basename(self.file);
        try w.print("{s}:{d} {s}\n", .{ name, self.line, self.msg() });
    }
};

pub fn basename(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfAny(u8, path, "/\\")) |i| {
        return path[i + 1 ..];
    }
    return path;
}

pub const Fail = error{ CompileFail, OutOfMemory };
