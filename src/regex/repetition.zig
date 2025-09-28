const std = @import("std");

pub const RepetitionRange = struct {
    min: usize,
    max: ?usize, // null means unlimited

    pub fn exact(count: usize) RepetitionRange {
        return .{
            .min = count,
            .max = count,
        };
    }

    pub fn atLeast(count: usize) RepetitionRange {
        return .{
            .min = count,
            .max = null,
        };
    }

    pub fn between(min: usize, max: usize) RepetitionRange {
        return .{
            .min = min,
            .max = max,
        };
    }
};

pub const RepetitionParser = struct {
    source: []const u8,
    pos: usize,

    pub fn init(source: []const u8) RepetitionParser {
        return .{
            .source = source,
            .pos = 0,
        };
    }

    pub fn parse(self: *RepetitionParser) !RepetitionRange {
        if (self.pos >= self.source.len or self.source[self.pos] != '{') {
            return error.InvalidRepetition;
        }
        self.pos += 1; // skip '{'

        const min = try self.parseNumber();
        if (self.pos >= self.source.len) {
            return error.UnterminatedRepetition;
        }

        if (self.source[self.pos] == '}') {
            self.pos += 1;
            return RepetitionRange.exact(min);
        }

        if (self.source[self.pos] != ',') {
            return error.InvalidRepetition;
        }
        self.pos += 1;

        if (self.pos >= self.source.len) {
            return error.UnterminatedRepetition;
        }

        if (self.source[self.pos] == '}') {
            self.pos += 1;
            return RepetitionRange.atLeast(min);
        }

        const max = try self.parseNumber();
        if (self.pos >= self.source.len or self.source[self.pos] != '}') {
            return error.UnterminatedRepetition;
        }
        self.pos += 1;

        if (max < min) {
            return error.InvalidRange;
        }

        return RepetitionRange.between(min, max);
    }

    fn parseNumber(self: *RepetitionParser) !usize {
        var num: usize = 0;
        var found_digit = false;

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c < '0' or c > '9') break;
            found_digit = true;
            num = num * 10 + (c - '0');
            self.pos += 1;
        }

        if (!found_digit) {
            return error.InvalidNumber;
        }

        return num;
    }
};
