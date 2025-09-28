const std = @import("std");

pub const CharSet = struct {
    // Using a bit set to efficiently store character ranges
    chars: std.StaticBitSet(256),
    is_negated: bool,

    pub fn init() CharSet {
        return .{
            .chars = std.StaticBitSet(256).initEmpty(),
            .is_negated = false,
        };
    }

    pub fn addChar(self: *CharSet, c: u8) void {
        self.chars.set(c);
    }

    pub fn addRange(self: *CharSet, start: u8, end: u8) void {
        var i: u16 = start;
        while (i <= end) : (i += 1) {
            self.chars.set(i);
        }
    }

    pub fn negate(self: *CharSet) void {
        self.is_negated = !self.is_negated;
        self.chars.toggleAll();
    }

    pub fn contains(self: *const CharSet, c: u8) bool {
        return self.chars.isSet(c) != self.is_negated;
    }

    // Add predefined character classes
    pub fn addDigits(self: *CharSet) void {
        self.addRange('0', '9');
    }

    pub fn addWhitespace(self: *CharSet) void {
        self.addChar(' ');
        self.addChar('\t');
        self.addChar('\n');
        self.addChar('\r');
        self.addChar('\x0C'); // form feed
    }

    pub fn addWord(self: *CharSet) void {
        self.addRange('a', 'z');
        self.addRange('A', 'Z');
        self.addRange('0', '9');
        self.addChar('_');
    }
};

pub const CharClassParser = struct {
    source: []const u8,
    pos: usize,
    charset: CharSet,

    pub fn init(source: []const u8) CharClassParser {
        return .{
            .source = source,
            .pos = 0,
            .charset = CharSet.init(),
        };
    }

    pub fn parse(self: *CharClassParser) !CharSet {
        // Check for negation
        if (self.pos < self.source.len and self.source[self.pos] == '^') {
            self.charset.is_negated = true;
            self.pos += 1;
        }

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            self.pos += 1;

            switch (c) {
                '\\' => try self.parseEscapeSequence(),
                '[' => {
                    if (self.pos < self.source.len and self.source[self.pos] == ':') {
                        try self.parsePOSIXClass();
                    } else {
                        self.charset.addChar(c);
                    }
                },
                '-' => {
                    if (self.pos > 1 and self.pos < self.source.len) {
                        const start = self.source[self.pos - 2];
                        const end = self.source[self.pos];
                        if (end < start) return error.InvalidRange;
                        self.charset.addRange(start, end);
                        self.pos += 1;
                    } else {
                        self.charset.addChar('-');
                    }
                },
                else => self.charset.addChar(c),
            }
        }

        return self.charset;
    }

    fn parseEscapeSequence(self: *CharClassParser) !void {
        if (self.pos >= self.source.len) return error.InvalidEscape;

        const c = self.source[self.pos];
        self.pos += 1;

        switch (c) {
            'd' => self.charset.addDigits(),
            'w' => self.charset.addWord(),
            's' => self.charset.addWhitespace(),
            'n' => self.charset.addChar('\n'),
            'r' => self.charset.addChar('\r'),
            't' => self.charset.addChar('\t'),
            else => self.charset.addChar(c),
        }
    }

    fn parsePOSIXClass(self: *CharClassParser) !void {
        self.pos += 1; // skip ':'
        const start = self.pos;
        
        while (self.pos < self.source.len) : (self.pos += 1) {
            if (self.source[self.pos] == ':' and 
                self.pos + 1 < self.source.len and 
                self.source[self.pos + 1] == ']') {
                const class_name = self.source[start..self.pos];
                self.pos += 2; // skip ':]'

                if (std.mem.eql(u8, class_name, "digit")) {
                    self.charset.addDigits();
                } else if (std.mem.eql(u8, class_name, "space")) {
                    self.charset.addWhitespace();
                } else if (std.mem.eql(u8, class_name, "alpha")) {
                    self.charset.addRange('a', 'z');
                    self.charset.addRange('A', 'Z');
                } else if (std.mem.eql(u8, class_name, "alnum")) {
                    self.charset.addRange('a', 'z');
                    self.charset.addRange('A', 'Z');
                    self.charset.addRange('0', '9');
                } else {
                    return error.InvalidPOSIXClass;
                }
                return;
            }
        }
        return error.UnterminatedPOSIXClass;
    }
};
