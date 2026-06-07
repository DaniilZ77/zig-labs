const std = @import("std");
const evaluator = @import("evaluator.zig");
const print = std.debug.print;
const testing = std.testing;

const BasicAllocator = struct {
    const Node = struct {
        used: usize,
        capacity: usize,
        block: usize,
        next: ?*Node,
    };
    state: ?*Node,
    child_allocator: std.mem.Allocator,
    print_debug: bool,
    const Node_alignment: std.mem.Alignment = .of(Node);

    pub fn init(ca: std.mem.Allocator, print_debug: bool) BasicAllocator {
        return .{
            .state = null,
            .child_allocator = ca,
            .print_debug = print_debug,
        };
    }

    fn free_block(self: *BasicAllocator, block: ?*Node) void {
        if (block) |node| {
            self.debug_info("freeing block {}\n", .{node.block});
            const node_buf = @as([*]u8, @ptrCast(@alignCast(node)))[0..node.capacity];
            self.child_allocator.rawFree(node_buf, Node_alignment, @returnAddress());
        }
    }

    fn debug_info(self: *BasicAllocator, comptime fmt: []const u8, args: anytype) void {
        if (!self.print_debug) {
            return;
        }
        print(fmt, args);
    }

    pub fn deinit(self: *BasicAllocator) void {
        var cur_node = self.state;
        var block_index: u64 = 0;
        if (self.state) |node| {
            block_index = node.block;
        }
        var block_first_node: ?*Node = self.state;
        while (cur_node) |node| {
            const next_node = node.next;
            cur_node = next_node;
            if (block_index == node.block) {
                continue;
            }
            self.free_block(block_first_node);
            block_first_node = node;
            block_index = node.block;
        }
        self.free_block(block_first_node);
    }

    pub fn allocator(self: *BasicAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn merge(self: *BasicAllocator, prev: ?*Node, curr: *Node, curr_index: u64) bool {
        const prev_node = prev orelse return false;
        if (curr.used != @sizeOf(Node) or prev_node.block != curr.block) {
            return false;
        }
        prev_node.capacity += curr.capacity;
        prev_node.next = curr.next;
        self.debug_info("merging node {} with node {} in block {}; new prev node: capacity={}; old curr node: capacity={}\n", .{
            curr_index - 1,
            curr_index,
            prev_node.block,
            prev_node.capacity,
            curr.capacity,
        });
        return true;
    }

    pub fn alloc(ctx: *anyopaque, size: usize, _: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *BasicAllocator = @ptrCast(@alignCast(ctx));
        var cur_node = self.state;
        var node_index: u64 = 0;
        var prev_node: ?*Node = null;
        const aligned_size = std.mem.alignForward(usize, @sizeOf(Node) + size, @alignOf(Node));
        while (cur_node) |node| : (cur_node = node.next) {
            node_index += 1;
            if (node.capacity - node.used < aligned_size) {
                if (!self.merge(prev_node, node, node_index)) {
                    prev_node = node;
                }
                continue;
            }
            const new_node_buf = @as([*]u8, @ptrCast(@alignCast(node)))[node.used..];
            const new_node: *Node = @ptrCast(@alignCast(new_node_buf));
            new_node.* = .{
                .used = aligned_size,
                .capacity = node.capacity - node.used,
                .block = node.block,
                .next = node.next,
            };
            node.next = new_node;
            node.capacity = node.used;

            self.debug_info("splitted node with index {} into two nodes; first node: used={}, capacity={}, block={}; second node: used={}, capacity={}, block={}\n", .{
                node_index,
                node.used,
                node.capacity,
                node.block,
                new_node.used,
                new_node.capacity,
                new_node.block,
            });

            return new_node_buf[@sizeOf(Node)..];
        }
        var next_block: u64 = 0;
        if (self.state) |node| {
            next_block = node.block + 1;
        }
        const block_size = std.mem.alignForward(usize, aligned_size, std.heap.page_size_max);
        const new_node_buf = self.child_allocator.rawAlloc(block_size, Node_alignment, @returnAddress()) orelse return null;
        const new_node: *Node = @ptrCast(@alignCast(new_node_buf));
        new_node.* = .{
            .used = aligned_size,
            .capacity = block_size,
            .block = next_block,
            .next = self.state,
        };
        self.state = new_node;

        if (new_node.next) |next_node| {
            self.debug_info("created new node: used={}, capacity={}, block={}; next node: used={}, capacity={}, block={}\n", .{
                new_node.used,
                new_node.capacity,
                new_node.block,
                next_node.used,
                next_node.capacity,
                next_node.block,
            });
        } else {
            self.debug_info("created new node: used={}, capacity={}, block={}; next node is null\n", .{
                new_node.used,
                new_node.capacity,
                new_node.block,
            });
        }

        return new_node_buf[@sizeOf(Node)..];
    }

    pub fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }

    pub fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }

    pub fn free(ctx: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
        const self: *BasicAllocator = @ptrCast(@alignCast(ctx));
        var cur_node = self.state;
        var node_index: u64 = 0;
        var prev_node: ?*Node = null;
        while (cur_node) |node| : (cur_node = node.next) {
            node_index += 1;
            const node_buf = @as([*]u8, @ptrCast(@alignCast(node)))[@sizeOf(Node)..];
            if (node_buf == buf.ptr) {
                node.used = @sizeOf(Node);
                self.debug_info("found node with index {} to deallocate; deallocated node: used={}, capacity={}\n", .{
                    node_index,
                    node.used,
                    node.capacity,
                });
                _ = self.merge(prev_node, node, node_index);
                return;
            }
            if (!self.merge(prev_node, node, node_index)) {
                prev_node = node;
            }
        }
    }
};

const TestStruct = struct {
    Field1: u64,
    Field2: f64,
    Field3: f32,
};

pub fn main(init: std.process.Init) !void {
    var basic_allocator = BasicAllocator.init(std.heap.page_allocator, true);
    defer basic_allocator.deinit();

    const allocator = basic_allocator.allocator();
    const test_structs1 = try allocator.alloc(TestStruct, 1000);
    const test_structs2 = try allocator.alloc(TestStruct, 1);
    const test_structs3 = try allocator.alloc(TestStruct, 2000);
    const test_structs4 = try allocator.alloc(TestStruct, 1);
    const test_structs5 = try allocator.alloc(TestStruct, 1);
    const test_structs6 = try allocator.alloc(TestStruct, 1);
    defer allocator.free(test_structs1);
    defer allocator.free(test_structs2);
    defer allocator.free(test_structs3);
    defer allocator.free(test_structs4);
    defer allocator.free(test_structs5);
    defer allocator.free(test_structs6);

    const io = init.io;
    const file = try std.Io.Dir.cwd().openFile(io, "input.txt", .{});
    defer file.close(io);

    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &file_buffer);

    const s = try reader.interface.takeDelimiter('\n');
    const numStr = try reader.interface.takeDelimiter('\n');
    const ctx = try std.fmt.parseFloat(f64, numStr orelse "0");

    var tokens = std.array_list.Managed(evaluator.Token).init(allocator);
    defer tokens.deinit();
    var iter = std.mem.tokenizeAny(u8, s orelse "", " ");
    while (iter.next()) |token| {
        try tokens.append(token);
    }

    const arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = evaluator.Parser.init(arena);
    const ev = try parser.parse(tokens.items, ctx);
    const res = evaluator.execute(ev);
    std.debug.print("{d}", .{res});
}
