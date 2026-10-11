const std = @import("std");
const builtin = @import("builtin");

inline fn MARK(comptime comment: []const u8) void {
    const prefix = switch (builtin.cpu.arch) {
        .x86, .x86_16, .x86_64, .riscv32, .riscv64 => "# ",
        .aarch64, .aarch64_be, .arm, .armeb, .thumb, .thumbeb => "// ",
        else => @compileError("MARK: unsupported architecture: {s}" ++ @tagName(builtin.cpu.arch)),
    };
    asm volatile (prefix ++ comment ::: .{});
}

const V: comptime_int = 32; // bytes (AVX)

const Entry = struct {
    key: []const u8 = &.{},

    hash: u64 = 0,
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

// line is always [100]u8;-?d?.d\n
// merykitty's solution
const ParsedTemp = struct {
    temp: i32,
    len: usize,
};

const MAGIC_MULTIPLIER: u64 = 100 * 0x1000000 + 10 * 0x10000 + 1; // 0x640A0001
inline fn parseDataPoint(word: u64) ParsedTemp {
    const negated = ~word;
    const sign: i64 = @as(i64, @bitCast(negated << 59)) >> 63; // -1 if '-', else 0
    const sign_u: u64 = @bitCast(sign);
    const without_sign = word & ~(sign_u & 0xFF);
    const dot: u6 = @intCast(@ctz(negated & 0x10101000)); //detecting DOT at byte 12, 20, 28
    const aligned = without_sign << @intCast(28 - @as(u32, dot));
    const digits = aligned & 0x0F000F0F00; // ASCII to digit mask
    const abs: i64 = @intCast(((digits *% MAGIC_MULTIPLIER) >> 32) & 0x3FF);
    return .{ .temp = @intCast((abs ^ sign) - sign), .len = (dot >> 3) + 3 };
}

pub fn main(init: std.process.Init) !void {
    // FALGS
    var args = init.minimal.args.iterate();
    _ = args.next();
    const arg = args.next() orelse "M";
    const DB_size = if (arg[0] == 'M') "100M" else "1B";
    const DB = try std.fmt.allocPrint(init.arena.allocator(), "../data/DB_{s}.txt", .{DB_size});
    const mode = args.next() orelse ""; // print [p]

    // FILE
    const file = try std.Io.Dir.cwd().openFile(init.io, DB, .{});
    defer file.close(init.io);

    // MMAP
    const size = (try file.stat(init.io)).size;
    const buf = try std.posix.mmap(
        null,
        size,
        .{ .READ = true },
        .{ .TYPE = .PRIVATE, .POPULATE = true },
        file.handle,
        0,
    );
    defer std.posix.munmap(buf);

    // HASH
    var stations: std.StringHashMapUnmanaged(Entry) = .empty;
    defer stations.deinit(init.gpa);

    var start: usize = 0;
    const fast_end = if (buf.len > 128) buf.len - 128 else 0;

    // BODY
    MARK("BODY_start");
    while (start < fast_end) {
        const sep = SemiIdx(buf, start);
        const name = buf[start..sep];
        const word = std.mem.readInt(u64, buf.ptr[sep + 1 ..][0..8], .little);
        const p = parseDataPoint(word);

        const gop = try stations.getOrPut(init.gpa, name);
        if (!gop.found_existing) { // empty
            gop.key_ptr.* = try init.arena.allocator().dupe(u8, name);
            gop.value_ptr.* = .{};
        }
        gop.value_ptr.Update(p.temp);

        start = sep + 1 + p.len;
    }
    MARK("BODY_end");

    // TAIL
    while (start < buf.len) {
        const nl = NLIdx(buf, start);
        defer start = nl + 1;

        const line = buf[start..nl];
        const sep = SemiReversedIdx(line);
        const name = line[0..sep];
        const temp = ParseTenths(line[sep + 1 ..]);

        const gop = try stations.getOrPut(init.gpa, name);
        if (!gop.found_existing) { // empty
            gop.key_ptr.* = try init.arena.allocator().dupe(u8, name);
            gop.value_ptr.* = .{};
        }
        gop.value_ptr.Update(temp);
    }

    if (std.mem.eql(u8, mode, "p")) { //mode:const, so translate
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
