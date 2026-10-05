const std = @import("std");

const V: comptime_int = 32; // bytes, 256bits (AVX)

const Statistics = struct {
    count: i32 = 0,
    min: f16 = std.math.inf(f16),
    sum: f64 = 0,
    max: f16 = -std.math.inf(f16),

    pub fn Average(self: Statistics) f64 {
        return self.sum / @as(f64, @floatFromInt(self.count));
    }
    pub fn Update(self: *Statistics, value: f16) void {
        self.count += 1;
        self.min = @min(self.min, value);
        self.sum += value;
        self.max = @max(self.max, value);
    }
};

fn SemiReversedIdx(line: []const u8) usize { // not null
    const n = @min(line.len, V);
    var buf: [V]u8 = @splat(0);
    @memcpy(buf[(V - n)..], line[(line.len - n)..]);
    const _mm: @Vector(V, u8) = buf;

    const semicol: @Vector(V, u8) = @splat(';');

    const mask: std.meta.Int(.unsigned, V) = @bitCast(_mm == semicol);
    return line.len + @as(usize, @ctz(mask)) - V; //ctz count backward
}

fn NLIdx(buf: []const u8, pos: usize) usize {
    //TODO: decomp is unrolled n%V or cmp+jmp
    const nl: @Vector(V, u8) = @splat('\n');
    var p = pos;
    while (p + V <= buf.len) : (p += V) {
        const chunk: @Vector(V, u8) = buf[p..][0..V].*;
        const m: std.meta.Int(.unsigned, V) = @bitCast(chunk == nl);
        if (m != 0) return p + @ctz(m);
    }
    return std.mem.indexOfScalarPos(u8, buf, p, '\n') orelse buf.len;
}

pub fn main(init: std.process.Init) !void {
    // FALGS
    var args = init.minimal.args.iterate();
    _ = args.next();
    const arg = args.next() orelse "M";
    const DB_size = if (arg[0] == 'M') "100M" else "1B";
    const DB = try std.fmt.allocPrint(init.arena.allocator(), "./data/DB_{s}.txt", .{DB_size});

    // FILE
    const file = try std.Io.Dir.cwd().openFile(init.io, DB, .{});
    defer file.close(init.io);

    // MMAP
    const size = (try file.stat(init.io)).size;
    const buf = try std.posix.mmap(null, size, .{ .READ = true }, .{ .TYPE = .PRIVATE, .POPULATE = true }, file.handle, 0);
    defer std.posix.munmap(buf);

    // HASH
    var stations: std.StringHashMapUnmanaged(Statistics) = .empty;
    defer stations.deinit(init.gpa);

    var start: usize = 0;
    while (start < buf.len) {
        const nl: usize = NLIdx(buf, start);
        defer start = nl + 1;
        const line = buf[start..nl];

        const separator: usize = SemiReversedIdx(line);
        const name = line[0..separator];
        const temp = std.fmt.parseFloat(f16, line[(separator + 1)..]) catch continue;

        const gop = try stations.getOrPut(init.gpa, name);
        if (!gop.found_existing) { // empty
            gop.key_ptr.* = try init.arena.allocator().dupe(u8, name);
            gop.value_ptr.* = .{};
        }
        gop.value_ptr.Update(temp);
    }

    if (false) {
        var c: usize = 0;
        var it = stations.iterator();
        while (it.next()) |entry| {
            const stats = entry.value_ptr.*;
            std.debug.print("[{s}] min:{d}, avg:{d:.1}, max:{d}\n", .{ entry.key_ptr.*, stats.min, stats.Average(), stats.max });
            c += 1;
            if (c >= 5) {
                break;
            }
        }
    }
}
