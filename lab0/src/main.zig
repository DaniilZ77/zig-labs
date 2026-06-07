const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();

    const path = args.next() orelse {
        std.debug.print("usage: zig run src/main.zig -- <input-file>\n", .{});
        return;
    };

    const input = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(input);

    var reader = std.Io.Reader.fixed(input);

    var pos: i64 = 50;
    var answer: usize = 0;

    while (true) {
        const raw_line = try reader.takeDelimiter('\n') orelse break;

        const line = std.mem.trim(u8, raw_line, " \r\n\t");
        if (line.len == 0) continue;

        const dir = line[0];
        const value = try std.fmt.parseInt(i64, line[1..], 10);

        switch (dir) {
            'L' => pos -= value,
            'R' => pos += value,
            else => return error.InvalidDirection,
        }

        pos = @mod(pos, 100);

        if (pos == 0) {
            answer += 1;
        }
    }

    std.debug.print("{d}\n", .{answer});
}
