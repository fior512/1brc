const std = @import("std");

const DB = "./data/DB.txt";
const V: comptime_int = 32; // bytes, 256bits (AVX)

const Statistics = struct {
    count: i32 = 0,
    min: f16 = std.math.inf(f16),
    avg: f16 = 0,
    max: f16 = -std.math.inf(f16),

    pub fn Average(self: *Statistics, new: f16) void {
        const n: f16 = @floatFromInt(self.count);
        self.avg = (new + self.avg) / n;
    }
    pub fn Min(self: *Statistics, new: f16) void {
        self.min = @min(self.min, new);
    }
    pub fn Max(self: *Statistics, new: f16) void {
        self.max = @max(self.max, new);
    }

    pub fn Do(self: *Statistics, value: f16) void {
        self.count += 1;
        self.Min(value);
        self.Average(value);
        self.Max(value);
    }
};

fn EscapeReversedIdx(line: []const u8) usize { // not null
    const n = @min(line.len, V);
    var buf: [V]u8 = @splat(0);
    @memcpy(buf[(V - n)..], line[(line.len - n)..]);
    const _mm: @Vector(V, u8) = buf;

    const semicol: @Vector(V, u8) = @splat(';');

    const mask: std.meta.Int(.unsigned, V) = @bitCast(_mm == semicol);
    return line.len + @as(usize, @ctz(mask)) - V; //ctz count backward
}

pub fn main(init: std.process.Init) !void {
    const file = try std.Io.Dir.cwd().openFile(init.io, DB, .{});
    defer file.close(init.io);

    var reader_buf: [6 * 1024]u8 = undefined;
    var reader = file.reader(init.io, &reader_buf);
    const stdin = &reader.interface;

    var stations: std.StringHashMapUnmanaged(Statistics) = .empty;
    defer stations.deinit(init.gpa);

    while (try stdin.takeDelimiter('\n')) |line| {
        if (line[0] == '#') continue; // 2 first lines are comments

        const separator: usize = EscapeReversedIdx(line);
        const name = line[0..separator];
        const temp = std.fmt.parseFloat(f16, line[(separator + 1)..]) catch continue;

        const gop = try stations.getOrPut(init.gpa, name);
        if (!gop.found_existing) { // empty
            gop.key_ptr.* = try init.arena.allocator().dupe(u8, name);
            gop.value_ptr.* = .{};
        }

        gop.value_ptr.Do(temp);
    }

    var c: usize = 0;
    var it = stations.iterator();
    while (it.next()) |entry| {
        const stats = entry.value_ptr.*;
        std.debug.print("[{s}] min:{d}, avg:{d}, max:{d}\n", .{ entry.key_ptr.*, stats.min, stats.avg, stats.max });
        c += 1;
        if (c >= 5) {
            break;
        }
    }
}
