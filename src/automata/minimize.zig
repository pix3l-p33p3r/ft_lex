const std = @import("std");
const DFA = @import("dfa.zig").DFA;
const DFAState = @import("dfa.zig").DFAState;

pub const MinimizedDFA = struct {
    dfa: DFA,

    pub fn init(allocator: std.mem.Allocator, input_dfa: *const DFA) !MinimizedDFA {
        var minimizer = DFAMinimizer.init(allocator, input_dfa);
        defer minimizer.deinit();

        return MinimizedDFA{
            .dfa = try minimizer.minimize(),
        };
    }

    pub fn deinit(self: *MinimizedDFA) void {
        self.dfa.deinit();
    }
};

const StateSet = std.StaticBitSet(256);
const PartitionId = usize;

pub const DFAMinimizer = struct {
    allocator: std.mem.Allocator,
    input_dfa: *const DFA,
    partitions: std.ArrayList(StateSet),
    state_to_partition: []PartitionId,
    worklist: std.ArrayList(PartitionId),
    alphabet: std.AutoHashMap(u21, void),

    pub fn init(allocator: std.mem.Allocator, input_dfa: *const DFA) DFAMinimizer {
        return .{
            .allocator = allocator,
            .input_dfa = input_dfa,
            .partitions = std.ArrayList(StateSet).init(allocator),
            .state_to_partition = undefined,
            .worklist = std.ArrayList(PartitionId).init(allocator),
            .alphabet = std.AutoHashMap(u21, void).init(allocator),
        };
    }

    pub fn deinit(self: *DFAMinimizer) void {
        self.partitions.deinit();
        self.worklist.deinit();
        self.alphabet.deinit();
        if (@hasField(@TypeOf(self.*), "state_to_partition")) {
            self.allocator.free(self.state_to_partition);
        }
    }

    fn collectAlphabet(self: *DFAMinimizer) !void {
        for (self.input_dfa.states.items) |state| {
            var it = state.transitions.keyIterator();
            while (it.next()) |symbol| {
                try self.alphabet.put(symbol.*, {});
            }
        }
    }

    fn initializePartitions(self: *DFAMinimizer) !void {
        // Create initial partitions: accepting and non-accepting states
        var accepting = StateSet.initEmpty();
        var nonaccepting = StateSet.initEmpty();

        for (self.input_dfa.states.items, 0..) |state, i| {
            if (state.is_accepting) {
                accepting.set(i);
            } else {
                nonaccepting.set(i);
            }
        }

        if (accepting.count() > 0) {
            try self.partitions.append(accepting);
            try self.worklist.append(0);
        }
        if (nonaccepting.count() > 0) {
            try self.partitions.append(nonaccepting);
            try self.worklist.append(self.partitions.items.len - 1);
        }

        // Initialize state to partition mapping
        self.state_to_partition = try self.allocator.alloc(PartitionId, self.input_dfa.states.items.len);
        for (0..self.input_dfa.states.items.len) |state| {
            self.state_to_partition[state] = if (accepting.isSet(state)) 0 else 1;
        }
    }

    fn splitPartition(self: *DFAMinimizer, partition_id: PartitionId, symbol: u21) !bool {
        const partition = self.partitions.items[partition_id];
        var transitions = std.AutoHashMap(PartitionId, StateSet).init(self.allocator);
        defer transitions.deinit();

        // Group states by their transition target partition
        var state_iter = partition.iterator(.{});
        while (state_iter.next()) |state| {
            const target_state = self.input_dfa.states.items[state].transitions.get(symbol) orelse continue;
            const target_partition = self.state_to_partition[target_state];

            var entry = try transitions.getOrPut(target_partition);
            if (!entry.found_existing) {
                entry.value_ptr.* = StateSet.initEmpty();
            }
            entry.value_ptr.set(state);
        }

        // If we found multiple groups, split the partition
        if (transitions.count() <= 1) return false;

        var new_partitions = std.ArrayList(StateSet).init(self.allocator);
        defer new_partitions.deinit();

        var it = transitions.valueIterator();
        while (it.next()) |states| {
            try new_partitions.append(states.*);
        }

        // Remove original partition and add new ones
        _ = self.partitions.swapRemove(partition_id);
        for (new_partitions.items) |new_partition| {
            const new_id = self.partitions.items.len;
            try self.partitions.append(new_partition);
            try self.worklist.append(new_id);

            // Update state to partition mapping
            var new_state_iter = new_partition.iterator(.{});
            while (new_state_iter.next()) |state| {
                self.state_to_partition[state] = new_id;
            }
        }

        return true;
    }

    pub fn minimize(self: *DFAMinimizer) !DFA {
        // Collect input alphabet
        try self.collectAlphabet();

        // Initialize partitions
        try self.initializePartitions();

        // Main minimization loop
        while (self.worklist.items.len > 0) {
            const partition_id = self.worklist.pop();
            var symbol_it = self.alphabet.keyIterator();
            while (symbol_it.next()) |symbol| {
                _ = try self.splitPartition(partition_id, symbol.*);
            }
        }

        // Build minimized DFA
        var min_dfa = DFA.init(self.allocator);
        errdefer min_dfa.deinit();

        // Create states for each partition
        var partition_to_state = try self.allocator.alloc(usize, self.partitions.items.len);
        defer self.allocator.free(partition_to_state);

        for (0..self.partitions.items.len) |i| {
            const state_id = try min_dfa.addState();
            partition_to_state[i] = state_id;

            // Find a representative state from the partition
            var it = self.partitions.items[i].iterator(.{});
            const rep_state = it.next() orelse continue;
            min_dfa.states.items[state_id].is_accepting = self.input_dfa.states.items[rep_state].is_accepting;
        }

        // Add transitions
        for (self.partitions.items, 0..) |partition, from_partition| {
            var state_iter = partition.iterator(.{});
            if (state_iter.next()) |rep_state| {
                var transition_iter = self.input_dfa.states.items[rep_state].transitions.iterator();
                while (transition_iter.next()) |entry| {
                    const symbol = entry.key_ptr.*;
                    const to_state = entry.value_ptr.*;
                    const to_partition = self.state_to_partition[to_state];

                    try min_dfa.states.items[partition_to_state[from_partition]].transitions.put(
                        symbol,
                        partition_to_state[to_partition]
                    );
                }
            }
        }

        // Set start state
        const start_partition = self.state_to_partition[self.input_dfa.start];
        min_dfa.start = partition_to_state[start_partition];

        return min_dfa;
    }
};
