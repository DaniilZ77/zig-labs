const std = @import("std");
const print = std.debug.print;

const C = struct {
    const Self = @This();

    deps: struct {
        a: *A,
        b: *B,
    },

    pub fn compute(_: *Self) !void {
        print("C\n", .{});
    }
};

const B = struct {
    const Self = @This();

    deps: struct {},

    pub fn compute(_: *Self) !void {
        print("B\n", .{});
    }
};

const A = struct {
    const Self = @This();

    deps: struct {},

    pub fn compute(_: *Self) !void {
        print("A\n", .{});
    }
};

const D = struct {
    const Self = @This();

    deps: struct {
        b: *B,
    },

    pub fn compute(_: *Self) !void {
        print("D\n", .{});
    }
};

const E = struct {
    const Self = @This();

    deps: struct {
        a: *C,
        b: *D,
    },

    pub fn compute(_: *Self) !void {
        print("E\n", .{});
    }
};

fn find(comptime Nodes: []const type, comptime T: type) usize {
    inline for (Nodes, 0..) |N, i| {
        if (N == T) return i;
    }
    @compileError("unknown node");
}

fn dfs(
    comptime Nodes: []const type,
    comptime i: usize,
    used: *[Nodes.len]bool,
    ord: *[Nodes.len]usize,
    pos: *usize,
) void {
    if (used[i]) return;
    used[i] = true;

    inline for (@typeInfo(@FieldType(Nodes[i], "deps")).@"struct".fields) |d| {
        dfs(Nodes, find(Nodes, @typeInfo(d.type).pointer.child), used, ord, pos);
    }

    ord[pos.*] = i;
    pos.* += 1;
}

fn sort(comptime Nodes: []const type) [Nodes.len]usize {
    var used = [_]bool{false} ** Nodes.len;
    var ord: [Nodes.len]usize = undefined;
    var pos: usize = 0;

    inline for (Nodes, 0..) |_, i| {
        dfs(Nodes, i, &used, &ord, &pos);
    }

    return ord;
}

pub fn GraphEvaluator(comptime Nodes: []const type) type {
    const sorted = sort(Nodes);

    return struct {
        const Self = @This();

        nodes: std.meta.Tuple(Nodes),

        pub fn init() Self {
            var self: Self = undefined;

            inline for (0..Nodes.len) |i| {
                inline for (@typeInfo(@FieldType(Nodes[i], "deps")).@"struct".fields) |d| {
                    @field(
                        @field(self.nodes, std.fmt.comptimePrint("{d}", .{i})).deps,
                        d.name,
                    ) = self.get(d.type);
                }
            }

            return self;
        }

        pub fn compute(self: *Self) !void {
            inline for (sorted) |i| {
                try @field(self.nodes, std.fmt.comptimePrint("{d}", .{i})).compute();
            }
        }

        pub fn get(self: *Self, comptime NodePtr: type) NodePtr {
            return &@field(
                self.nodes,
                std.fmt.comptimePrint("{d}", .{find(Nodes, @typeInfo(NodePtr).pointer.child)}),
            );
        }
    };
}

pub fn main() !void {
    var evaluator = GraphEvaluator(&.{ E, D, A, B, C }).init();
    try evaluator.compute();
    const d = evaluator.get(*D);
    _ = d;
}
