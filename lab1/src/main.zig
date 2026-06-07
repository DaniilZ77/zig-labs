const std = @import("std");

const VTable = struct {
    eval: *const fn (*anyopaque) f64,
};

const Evaluator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,
};

fn execute(e: Evaluator) f64 {
    return e.vtable.eval(e.ptr);
}

const Primitive = struct {
    v: f64,

    pub fn eval(ptr: *anyopaque) f64 {
        const t: *Primitive = @ptrCast(@alignCast(ptr));
        return t.v;
    }

    pub fn init(v: f64) Primitive {
        return Primitive{
            .v = v,
        };
    }

    pub fn interface(self: *Primitive) Evaluator {
        return Evaluator{
            .ptr = self,
            .vtable = &VTable{
                .eval = &eval,
            },
        };
    }
};

const Plus = struct {
    left: Evaluator,
    right: Evaluator,

    pub fn eval(ptr: *anyopaque) f64 {
        const t: *Plus = @ptrCast(@alignCast(ptr));
        return execute(t.left) + execute(t.right);
    }

    pub fn init(l: Evaluator, r: Evaluator) Plus {
        return Plus{
            .left = l,
            .right = r,
        };
    }

    pub fn interface(self: *Plus) Evaluator {
        return Evaluator{
            .ptr = self,
            .vtable = &VTable{
                .eval = &eval,
            },
        };
    }
};

const Minus = struct {
    left: Evaluator,
    right: Evaluator,

    pub fn eval(ptr: *anyopaque) f64 {
        const t: *Minus = @ptrCast(@alignCast(ptr));
        return execute(t.left) - execute(t.right);
    }

    pub fn init(l: Evaluator, r: Evaluator) Minus {
        return Minus{
            .left = l,
            .right = r,
        };
    }

    pub fn interface(self: *Minus) Evaluator {
        return Evaluator{
            .ptr = self,
            .vtable = &VTable{
                .eval = &eval,
            },
        };
    }
};

const Sqrt = struct {
    v: Evaluator,

    pub fn eval(ptr: *anyopaque) f64 {
        const t: *Sqrt = @ptrCast(@alignCast(ptr));
        return std.math.sqrt(execute(t.v));
    }

    pub fn init(v: Evaluator) Sqrt {
        return Sqrt{
            .v = v,
        };
    }

    pub fn interface(self: *Sqrt) Evaluator {
        return Evaluator{
            .ptr = self,
            .vtable = &VTable{
                .eval = &eval,
            },
        };
    }
};

const Token = []const u8;

const Parser = struct {
    allocator: std.heap.ArenaAllocator,

    const unit = struct {
        u: Evaluator,
        other: ?[]const Token,
    };

    pub fn init(allocator: std.heap.ArenaAllocator) Parser {
        return Parser{
            .allocator = allocator,
        };
    }

    fn allocUnit(self: *Parser, comptime T: type, data: anytype) !*T {
        const ptr = try self.allocator.allocator().create(T);
        ptr.* = data;
        return ptr;
    }

    pub fn parse(self: *Parser, tokens: []const Token, ctx: f64) !Evaluator {
        const res = try self.parseInternal(tokens, ctx);
        return res.u;
    }

    fn parseInternal(self: *Parser, tokens: []const Token, ctx: f64) !unit {
        if (tokens.len == 0) {
            const au = try self.allocUnit(Primitive, Primitive.init(0));
            return unit{
                .u = au.interface(),
                .other = null,
            };
        }

        const cmd = tokens[0];
        if (cmd.len == 0) {
            return try self.parseInternal(tokens[1..], ctx);
        }

        if (std.mem.eql(u8, cmd, "sqrt")) {
            const p = try self.parseInternal(tokens[1..], ctx);
            const au = try self.allocUnit(Sqrt, Sqrt.init(p.u));
            return unit{
                .u = au.interface(),
                .other = p.other,
            };
        }
        if (cmd.len == 1) {
            if (cmd[0] == '+' or cmd[0] == '-') {
                const p1 = try self.parseInternal(tokens[1..], ctx);
                const p2 = try self.parseInternal(p1.other orelse &[_]Token{}, ctx);
                var u = unit{
                    .u = undefined,
                    .other = p2.other,
                };
                if (cmd[0] == '+') {
                    const au = try self.allocUnit(Plus, Plus.init(p1.u, p2.u));
                    u.u = au.interface();
                } else if (cmd[0] == '-') {
                    const au = try self.allocUnit(Minus, Minus.init(p1.u, p2.u));
                    u.u = au.interface();
                }
                return u;
            } else if (cmd[0] == 'x') {
                const au = try self.allocUnit(Primitive, Primitive.init(ctx));
                return unit{
                    .u = au.interface(),
                    .other = tokens[1..],
                };
            }
        }

        const num = try std.fmt.parseFloat(f64, cmd);
        const au = try self.allocUnit(Primitive, Primitive.init(num));
        return unit{
            .u = au.interface(),
            .other = tokens[1..],
        };
    }
};

pub fn main() !void {
    const file = try std.fs.cwd().openFile("input.txt", .{});
    defer file.close();

    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(&file_buffer);

    const s = try reader.interface.takeDelimiter('\n');
    const numStr = try reader.interface.takeDelimiter('\n');
    const ctx = try std.fmt.parseFloat(f64, numStr orelse "0");

    var tokens = std.array_list.Managed(Token).init(std.heap.page_allocator);
    defer tokens.deinit();
    var iter = std.mem.tokenizeAny(u8, s orelse "", " ");
    while (iter.next()) |token| {
        try tokens.append(token);
    }

    const arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var parser = Parser.init(arena);
    const ev = try parser.parse(tokens.items, ctx);
    const res = execute(ev);
    std.debug.print("{d}", .{res});
}
