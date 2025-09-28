const std = @import("std");
const NFA = @import("nfa.zig").NFA;
const EPSILON = @import("nfa.zig").EPSILON;

pub const DFAState = struct {
    transitions: std.AutoHashMap(u21, usize),
    is_accepting: bool,
    action: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) DFAState {
        return .{
            .transitions = std.AutoHashMap(u21, usize).init(allocator),
            .is_accepting = false,
            .action = null,
        };
    }

    pub fn deinit(self: *DFAState) void {
        self.transitions.deinit();
    }
};

pub const DFA = struct {
    states: std.ArrayList(DFAState),
    start: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DFA {
        return .{
            .states = std.ArrayList(DFAState).init(allocator),
            .start = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DFA) void {
        for (self.states.items) |*state| {
            state.deinit();
        }
        self.states.deinit();
    }

    pub fn addState(self: *DFA) !usize {
        const idx = self.states.items.len;
        try self.states.append(DFAState.init(self.allocator));
        return idx;
    }

    /// Converts an NFA to a DFA using the subset construction algorithm
    pub fn fromNFA(allocator: std.mem.Allocator, nfa: *const NFA) !DFA {
        var dfa = DFA.init(allocator);
        errdefer dfa.deinit();

        // Map from NFA state sets to DFA state indices
        var state_map = std.AutoHashMap(u64, usize).init(allocator);
        defer state_map.deinit();

        // Queue of unprocessed DFA states
        var queue = std.ArrayList(struct { 
            dfa_state: usize, 
            nfa_states: std.StaticBitSet(256) 
        }).init(allocator);
        defer queue.deinit();

        // Create initial state from NFA start state's epsilon closure
        var initial_states = std.StaticBitSet(256).initEmpty();
        try epsilonClosure(nfa, nfa.start, &initial_states);
        const initial_dfa_state = try dfa.addState();
        dfa.start = initial_dfa_state;

        // Set accepting if any NFA state in the set is accepting
        dfa.states.items[initial_dfa_state].is_accepting = isAccepting(nfa, &initial_states);

        try state_map.put(hashStateSet(&initial_states), initial_dfa_state);
        try queue.append(.{ .dfa_state = initial_dfa_state, .nfa_states = initial_states });

        // Process queue until empty
        while (queue.items.len > 0) {
            const current = queue.pop();
            const current_dfa_state = current.dfa_state;
            const current_nfa_states = current.nfa_states;

            // Find all possible input symbols from current NFA states
            var inputs = std.AutoHashMap(u21, void).init(allocator);
            defer inputs.deinit();

            var state_iter = current_nfa_states.iterator(.{});
            while (state_iter.next()) |nfa_state| {
                var transitions = nfa.states.items[nfa_state].transitions;
                var it = transitions.iterator();
                while (it.next()) |entry| {
                    const input = entry.key_ptr.*;
                    if (input != EPSILON) {
                        try inputs.put(input, {});
                    }
                }
            }

            // For each input symbol, compute next state set
            var input_iter = inputs.keyIterator();
            while (input_iter.next()) |input| {
                var next_states = std.StaticBitSet(256).initEmpty();
                
                // Compute next states for this input
                var state_iter2 = current_nfa_states.iterator(.{});
                while (state_iter2.next()) |nfa_state| {
                    if (nfa.states.items[nfa_state].transitions.get(input.*)) |targets| {
                        for (targets.items) |target| {
                            try epsilonClosure(nfa, target, &next_states);
                        }
                    }
                }

                const hash = hashStateSet(&next_states);
                const next_dfa_state = if (state_map.get(hash)) |existing| existing else blk: {
                    const new_state = try dfa.addState();
                    try state_map.put(hash, new_state);
                    dfa.states.items[new_state].is_accepting = isAccepting(nfa, &next_states);
                    try queue.append(.{ 
                        .dfa_state = new_state, 
                        .nfa_states = next_states 
                    });
                    break :blk new_state;
                };

                try dfa.states.items[current_dfa_state].transitions.put(input.*, next_dfa_state);
            }
        }

        return dfa;
    }
};

fn epsilonClosure(nfa: *const NFA, state: usize, result: *std.StaticBitSet(256)) !void {
    if (result.isSet(state)) return;
    result.set(state);

    if (nfa.states.items[state].transitions.get(EPSILON)) |targets| {
        for (targets.items) |target| {
            try epsilonClosure(nfa, target, result);
        }
    }
}

fn isAccepting(nfa: *const NFA, states: *const std.StaticBitSet(256)) bool {
    var it = states.iterator(.{});
    while (it.next()) |state| {
        if (nfa.states.items[state].is_accepting) {
            return true;
        }
    }
    return false;
}

fn hashStateSet(states: *const std.StaticBitSet(256)) u64 {
    var hasher = std.hash.Wyhash.init(0);
    const bytes = std.mem.sliceAsBytes(states.masks());
    hasher.update(bytes);
    return hasher.final();
}
