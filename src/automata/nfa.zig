const std = @import("std");

/// Special epsilon transition that doesn't consume input
pub const EPSILON = 0;

pub const State = struct {
    transitions: std.AutoHashMap(u21, std.ArrayList(usize)),
    is_accepting: bool,
    action: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) State {
        return .{
            .transitions = std.AutoHashMap(u21, std.ArrayList(usize)).init(allocator),
            .is_accepting = false,
            .action = null,
        };
    }

    pub fn deinit(self: *State) void {
        var it = self.transitions.valueIterator();
        while (it.next()) |value| {
            value.deinit();
        }
        self.transitions.deinit();
    }

    pub fn addTransition(self: *State, input: u21, target: usize, allocator: std.mem.Allocator) !void {
        var targets = self.transitions.get(input) orelse {
            var new_list = std.ArrayList(usize).init(allocator);
            try self.transitions.put(input, new_list);
            try new_list.append(target);
            return;
        };
        try targets.append(target);
    }
};

pub const NFA = struct {
    states: std.ArrayList(State),
    start: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) NFA {
        return .{
            .states = std.ArrayList(State).init(allocator),
            .start = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NFA) void {
        for (self.states.items) |*state| {
            state.deinit();
        }
        self.states.deinit();
    }

    pub fn addState(self: *NFA) !usize {
        const idx = self.states.items.len;
        try self.states.append(State.init(self.allocator));
        return idx;
    }

    pub fn addTransition(self: *NFA, from: usize, input: u21, to: usize) !void {
        try self.states.items[from].addTransition(input, to, self.allocator);
    }

    /// Creates a basic NFA that matches a single character
    pub fn forChar(allocator: std.mem.Allocator, c: u21) !NFA {
        var nfa = NFA.init(allocator);
        errdefer nfa.deinit();

        const start = try nfa.addState();
        const end = try nfa.addState();
        try nfa.addTransition(start, c, end);
        nfa.states.items[end].is_accepting = true;
        nfa.start = start;
        return nfa;
    }

    /// Creates a basic NFA that matches the empty string
    pub fn forEpsilon(allocator: std.mem.Allocator) !NFA {
        var nfa = NFA.init(allocator);
        errdefer nfa.deinit();

        const start = try nfa.addState();
        nfa.states.items[start].is_accepting = true;
        nfa.start = start;
        return nfa;
    }

    /// Concatenates two NFAs
    pub fn concat(self: *NFA, other: *NFA) !void {
        const offset = self.states.items.len;
        
        // Add all states from other NFA
        for (other.states.items) |state| {
            var new_state = try self.addState();
            self.states.items[new_state].is_accepting = state.is_accepting;
            
            var it = state.transitions.iterator();
            while (it.next()) |entry| {
                const input = entry.key_ptr.*;
                for (entry.value_ptr.*.items) |target| {
                    try self.addTransition(new_state, input, target + offset);
                }
            }
        }

        // Connect accepting states of first NFA to start state of second NFA
        for (self.states.items, 0..) |*state, i| {
            if (state.is_accepting) {
                state.is_accepting = false;
                try self.addTransition(i, EPSILON, other.start + offset);
            }
        }
    }

    /// Creates union of two NFAs (matches either one)
    pub fn unionWith(self: *NFA, other: *NFA) !void {
        const old_start = self.start;
        const other_len = other.states.items.len;
        
        // Add all states from other NFA
        for (other.states.items) |state| {
            var new_state = try self.addState();
            self.states.items[new_state].is_accepting = state.is_accepting;
            
            var it = state.transitions.iterator();
            while (it.next()) |entry| {
                const input = entry.key_ptr.*;
                for (entry.value_ptr.*.items) |target| {
                    try self.addTransition(new_state, input, target + other_len);
                }
            }
        }

        // Create new start state
        const new_start = try self.addState();
        try self.addTransition(new_start, EPSILON, old_start);
        try self.addTransition(new_start, EPSILON, other.start + other_len);
        self.start = new_start;
    }

    /// Creates a repeated version of the NFA based on min and max repetitions
    pub fn repeat(self: *NFA, min: usize, max: ?usize) !void {
        // Handle unlimited repetitions (Kleene star/plus)
        if (min == 0 and max == null) {
            return self.star();
        }
        if (min == 1 and max == null) {
            return self.plus();
        }

        // Create exact copies for minimum repetitions
        var concatenated = try self.clone();
        defer concatenated.deinit();

        var i: usize = 1;
        while (i < min) : (i += 1) {
            var copy = try self.clone();
            try concatenated.concat(&copy);
            copy.deinit();
        }

        // Add optional copies for additional repetitions up to max
        if (max) |maximum| {
            var j: usize = min;
            while (j < maximum) : (j += 1) {
                var copy = try self.clone();
                try copy.optional();
                try concatenated.concat(&copy);
                copy.deinit();
            }
        }

        // Replace self with concatenated version
        self.deinit();
        self.* = concatenated;
    }

    /// Creates positive closure of the NFA (matches one or more repetitions)
    pub fn plus(self: *NFA) !void {
        const old_start = self.start;
        
        // Add epsilon transitions from accepting states back to start
        for (self.states.items, 0..) |state, i| {
            if (state.is_accepting) {
                try self.addTransition(i, EPSILON, old_start);
            }
        }
    }

    /// Makes the NFA optional (matches zero or one repetition)
    pub fn optional(self: *NFA) !void {
        const old_start = self.start;
        const new_start = try self.addState();

        // Add epsilon transitions from new start to old start and make new start accepting
        try self.addTransition(new_start, EPSILON, old_start);
        self.states.items[new_start].is_accepting = true;
        self.start = new_start;
    }
};
