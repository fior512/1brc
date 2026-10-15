const std = @import("std");
const builtin = @import("builtin");

const V: comptime_int = 32; // bytes (AVX)

inline fn MARK(comptime comment: []const u8) void {
    const prefix = switch (builtin.cpu.arch) {
        .x86, .x86_16, .x86_64, .riscv32, .riscv64 => "# ",
        .aarch64, .aarch64_be, .arm, .armeb, .thumb, .thumbeb => "// ",
        else => @compileError("MARK: unsupported architecture: {s}" ++ @tagName(builtin.cpu.arch)),
    };
    asm volatile (prefix ++ comment ::: .{});
}

const Map = std.HashMapUnmanaged([]const u8, Entry, Ctx, 50);
const Buf = []align(std.heap.page_size_min) u8;
const Ctx = struct {
    pub fn hash(_: Ctx, k: []const u8) u64 {
        const w: u64 = if (k.len >= 8)
            std.mem.readInt(u64, k[0..8], .little)
        else blk: {
            var t: u64 = 0;
            for (k, 0..) |c, i| t |= @as(u64, c) << @intCast(8 * i);
            break :blk t;
        };
        const h = (w ^ k.len) *% 0x9E3779B97F4A7C15;
        return h ^ (h >> 32); // fold high bits down: std map indexes with LOW bits
    }
    pub fn eql(_: Ctx, a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

const Entry = struct {
    sum: i64 = 0,
    count: i32 = 0,
    min: i32 = std.math.maxInt(i32),
    max: i32 = std.math.minInt(i32),

    pub fn Update(self: *Entry, value: i32) void {
        self.count += 1;
        self.min = @min(self.min, value);
        self.sum += value;
        self.max = @max(self.max, value);
    }
    pub fn Average(self: Entry) f64 {
        return @as(f64, @floatFromInt(self.sum)) / @as(f64, @floatFromInt(self.count));
    }

    pub fn Fuse(self: *Entry, sub: Entry) void {
        self.count += sub.count;
        self.min = @min(self.min, sub.min);
        self.sum += sub.sum;
        self.max = @max(self.max, sub.max);
    }
};

fn ParseTenths(str: []const u8) i32 {
    const is_negative: i32 = @intFromBool(str[0] == '-');
    const number = str[@intCast(is_negative)..];
    const len = number.len;

    const hundreds_digit: i32 = if (len == 4) number[0] - '0' else 0;
    const value = hundreds_digit * 100 + @as(
        i32,
        number[len - 3] - '0',
    ) * 10 + (number[len - 1] - '0');

    return (value ^ -is_negative) + is_negative;
}

inline fn SemiIdx(buf: []const u8, start: usize) usize { // BODY: no EOL assumption
    const v: @Vector(V, u8) = buf.ptr[start..][0..V].*; // direct load (no memcpy)
    const semi: @Vector(V, u8) = @splat(';');
    const mask: std.meta.Int(.unsigned, V) = @bitCast(v == semi);
    if (mask != 0) return start + @ctz(mask); // first ';' after start
    return std.mem.indexOfScalarPos(u8, buf, start + V, ';').?; // name ≥ 32 B (rare)
}

fn SemiReversedIdx(line: []const u8) usize { // TAIL: assume known EOL
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

inline fn update(
    arena: std.mem.Allocator,
    stations: *Map,
    name: []const u8,
    temp: i32,
) !void {
    const gop = stations.getOrPutAssumeCapacity(name);
    if (!gop.found_existing) {
        gop.key_ptr.* = try arena.dupe(u8, name);
        gop.value_ptr.* = .{};
    }
    gop.value_ptr.Update(temp);
}

inline fn worker(
    arena: std.mem.Allocator,
    buf: []const u8,
    out: *Map,
) !void {

    // HASH
    var stations: Map = .empty;
    try stations.ensureTotalCapacity(arena, 1 << 15);

    var start: usize = 0;
    const fast_end = if (buf.len > 128) buf.len - 128 else 0;

    // BODY
    while (start < fast_end) {
        const sep = SemiIdx(buf, start);
        const name = buf[start..sep];
        const vec = std.mem.readInt(u64, buf.ptr[sep + 1 ..][0..8], .little);
        const p = parseDataPoint(vec);

        try update(arena, &stations, name, p.temp);
        start = sep + 1 + p.len;
    }

    // TAIL
    while (start < buf.len) {
        const nl = NLIdx(buf, start);
        defer start = nl + 1;

        const line = buf[start..nl];
        const sep = SemiReversedIdx(line);
        const name = line[0..sep];
        const temp = ParseTenths(line[sep + 1 ..]);

        try update(arena, &stations, name, temp);
    }
    out.* = stations;
}

// vec;
// line is always [100]u8;-?d?.d\n
// merykitty's solution
const MAGIC_MULTIPLIER: u64 = 100 * 0x1000000 + 10 * 0x10000 + 1; // 0x640A0001
inline fn parseDataPoint(vec: u64) struct {
    temp: i32,
    len: usize,
} {
    const negated = ~vec;
    const sign: i64 = @as(i64, @bitCast(negated << 59)) >> 63; // -1 if '-', else 0
    const sign_u: u64 = @bitCast(sign);
    const without_sign = vec & ~(sign_u & 0xFF);
    const dot: u6 = @intCast(@ctz(negated & 0x10101000)); //detecting DOT at byte 12, 20, 28
    const aligned = without_sign << @intCast(28 - @as(u32, dot));
    const digits = aligned & 0x0F000F0F00; // ASCII to digit mask
    const abs: i64 = @intCast(((digits *% MAGIC_MULTIPLIER) >> 32) & 0x3FF);
    return .{ .temp = @intCast((abs ^ sign) - sign), .len = (dot >> 3) + 3 };
}

pub fn flags(args: anytype, arena: std.mem.Allocator) !struct { //TODO:find iterator type
    DB: []const u8,
    print: []const u8,
    threads: u32,
} {
    var it = args;
    _ = it.next();
    const arg = it.next() orelse "M";
    const DB_size = if (arg.len > 0 and arg[0] == 'M') "100M" else "1B";
    const DB = try std.fmt.allocPrint(arena, "../data/DB_{s}.txt", .{DB_size});
    const print = it.next() orelse "";
    const threads_arg = it.next() orelse "8";
    const threads = try std.fmt.parseInt(u32, threads_arg, 10);

    return .{
        .DB = DB,
        .print = print,
        .threads = threads,
    };
}

pub fn main(init: std.process.Init) !void {
    // FLAGS
    const args = try flags(init.minimal.args.iterate(), init.arena.allocator());

    // FILE
    const file = try std.Io.Dir.cwd().openFile(init.io, args.DB, .{});
    defer file.close(init.io);

    //MMAP
    const size = (try file.stat(init.io)).size;
    const chunk = size / args.threads;

    const whole = try std.posix.mmap(
        null,
        size,
        .{ .READ = true },
        .{ .TYPE = .PRIVATE, .POPULATE = true },
        file.handle,
        0,
    );
    defer std.posix.munmap(whole);


    // Multi HOTPATH
    const handles = try init.arena.allocator().alloc(std.Thread, args.threads);

    const arenas = try init.arena.allocator().alloc(std.heap.ArenaAllocator, args.threads);
    for (arenas) |*a| a.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer for (arenas) |*a| a.deinit();

    const results = try init.arena.allocator().alloc(Map, args.threads);
    for (0..args.threads) |t| {
        const raw_start = chunk * t;
        const raw_end = if (t == args.threads - 1) size else chunk * (t + 1);

        const start = if (raw_start == 0 or whole[raw_start - 1] == '\n') raw_start else NLIdx(
            whole,
            raw_start,
        ) + 1;

        const end = if (raw_end == size) size else NLIdx(whole, raw_end - 1) + 1;

        handles[t] = try std.Thread.spawn(
            .{},
            worker,
            .{ arenas[t].allocator(), whole[start..end], &results[t] },
        );
    }
    for (handles) |h| h.join();

    // MERGE
    var stations: Map = .empty;
    for (results) |hashmap| {
        var it = hashmap.iterator();
        while (it.next()) |entry| {
            const gop = try stations.getOrPut(init.arena.allocator(), entry.key_ptr.*);
            if (!gop.found_existing) {
                gop.key_ptr.* = try init.arena.allocator().dupe(u8, entry.key_ptr.*);
                gop.value_ptr.* = .{};
            }
            gop.value_ptr.Fuse(entry.value_ptr.*);
        }
    }

    // PRINT
    if (std.mem.eql(u8, args.print, "p")) {
        var c: usize = 0;
        var it = stations.iterator();
        while (it.next()) |entry| {
            std.debug.print(
                "[{s}] min:{d}, avg:{d:.1}, max:{d}\n",
                .{
                    entry.key_ptr.*,
                    @as(f32, @floatFromInt(entry.value_ptr.min)) / 10,
                    entry.value_ptr.Average() / 10,
                    @as(f32, @floatFromInt(entry.value_ptr.max)) / 10,
                },
            );
            c += 1;
            if (c >= 5) {
                break;
            }
        }
    }
}
