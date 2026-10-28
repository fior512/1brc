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

const TABLE_BITS = 15;
const TABLE_SLOTS = 1 << TABLE_BITS;
const Slot = struct {
    pword: [*]const u8,
    pword_len: u64,
    sum: i64,
    count: i32,
    min: i32,
    max: i32,

    probe_total: u64, // lifetime
    probe_max: u64, // single sequence
    lookup_count: u64, // calls
};

const Table = struct {
    // AoS with linear probing instead of HM.
    // - Compile time size, no alloc
    // - fixed size words with fast path-prefix
    // - cheap hash
    // - SIMD pword comparison
    slots: []Slot, //AoS

    fn init(arena: std.mem.Allocator) !Table {
        const slots = try arena.alignedAlloc(Slot, .@"64", TABLE_SLOTS);
        // .@"64" is an enum litteral for alignement size, @ is here to allow names starting with number
        @memset(std.mem.sliceAsBytes(slots), 0);
        return .{ .slots = slots };
    }

    inline fn hash(word: u64, len: usize) u64 {
        //(1+ sqrt(5))/2 = @as(u64, 1.6180339887)
        return (word ^ len) *% 0x9E3779B97F4A7C15;
    }

    inline fn eqlKey(a: [*]const u8, b: [*]const u8, len: usize) bool {
        if (len >= 16) {
            var i: usize = 0;
            while (i + 16 < len) : (i += 16) {
                const x: @Vector(16, u8) = a[i..][0..16].*;
                const y: @Vector(16, u8) = b[i..][0..16].*;
                if (!@reduce(.And, x == y)) return false;
            }
            const x: @Vector(16, u8) = a[len - 16 ..][0..16].*;
            const y: @Vector(16, u8) = b[len - 16 ..][0..16].*;
            return @reduce(.And, x == y);
        }
        if (len >= 8) {
            const x0 = std.mem.readInt(u64, a[0..8], .little);
            const y0 = std.mem.readInt(u64, b[0..8], .little);
            const x1 = std.mem.readInt(u64, a[len - 8 ..][0..8], .little);
            const y1 = std.mem.readInt(u64, b[len - 8 ..][0..8], .little);
            return (x0 == y0) and (x1 == y1);
        }
        if (len >= 4) {
            const x0 = std.mem.readInt(u32, a[0..4], .little);
            const y0 = std.mem.readInt(u32, b[0..4], .little);
            const x1 = std.mem.readInt(u32, a[len - 4 ..][0..4], .little);
            const y1 = std.mem.readInt(u32, b[len - 4 ..][0..4], .little);
            return (x0 == y0) and (x1 == y1);
        }
        for (0..len) |i| if (a[i] != b[i]) return false;
        return true;
    }
    inline fn find(self: *Table, pword: [*]const u8, len: usize, word: u64) *Slot {
        // TODO:
        //     - SIMD
        //     - fingerprint/control byte as Bloom if long probe sequence (delayed activation over P(len) ?)
        //
        //     B: probe_total=93800, probe_max=10, lookup_count=77392
        var i: usize = @intCast(hash(word, len) >> (64 - TABLE_BITS)); // logical slot in AoS
        var probes: u64 = 0;
        while (true) : (i = (i + 1) & (TABLE_SLOTS - 1)) { // linear probing if occupied
            probes += 1;
            const s = &self.slots[i];
            if (s.pword_len == len and eqlKey(s.pword, pword, len)) {
                s.probe_total += probes;
                s.probe_max = @max(s.probe_max, probes);
                s.lookup_count += 1;
                return s;
            } // found
            if (s.pword_len == 0) { // empty slot (real or probing)
                s.* = .{
                    .pword = pword,
                    .sum = 0,
                    .pword_len = @intCast(len),
                    .count = 0,
                    .min = std.math.maxInt(i32),
                    .max = std.math.minInt(i32),

                    .probe_total = probes,
                    .probe_max = probes,
                    .lookup_count = 1,
                };
                return s;
            }

        }
    }

    inline fn prefixSafe(pword: [*]const u8, len: usize) u64 {
        // EOF safe
        var t: [8]u8 = @splat(0);
        const n = @min(len, 8);
        @memcpy(t[0..n], pword[0..n]);
        return std.mem.readInt(u64, &t, .little);
    }

    inline fn prefixFast(pword: [*]const u8, len: usize) u64 {
        // UB OOBound
        const word = std.mem.readInt(u64, pword[0..8], .little);
        const glight: u64 = 
            if (len >= 8) ~@as(u64, 0) // 0xFFF..
            else (@as(u64, 1) << @intCast(8 * len)) - 1; // or 0x1FF-1=0xFF..
        return word & glight;
    }

    inline fn record(self: *Table, pword: [*]const u8, len: usize, word: u64, temp: i32) void {
        //nasty API due to prefix* optimization (pword U word)
        const s = self.find(pword, len, word);
        s.count += 1;
        s.min = @min(s.min, temp);
        s.sum += temp;
        s.max = @max(s.max, temp);
    }

    inline fn fuse(self: *Table, other: Slot) void {
        const s = self.find(other.pword, other.pword_len, prefixSafe(other.pword, other.pword_len));
        s.count += other.count;
        s.min = @min(s.min, other.min);
        s.sum += other.sum;
        s.max = @max(s.max, other.max);
    }
};

inline fn ParseTenths(str: []const u8) i32 {
    const is_negative: i32 = @intFromBool(str[0] == '-');
    const number = str[@intCast(is_negative)..];
    const len = number.len;

    const hundreds_digit: i32 = if (len == 4) number[0] - '0' else 0;
    const value = 
        hundreds_digit 
        * 100 
        + @as(i32, number[len - 3] - '0')
        * 10
        + (number[len - 1] - '0');

    return (value ^ -is_negative) + is_negative;
}

inline fn SemiIdx(buf: []const u8, start: usize) usize { // BODY: no EOL assumption
    const v: @Vector(V, u8) = buf.ptr[start..][0..V].*; // direct load (no memcpy)
    const semi: @Vector(V, u8) = @splat(';');
    const mask: std.meta.Int(.unsigned, V) = @bitCast(v == semi);
    if (mask != 0) return start + @ctz(mask); // first ';' after start
    return std.mem.indexOfScalarPos(u8, buf, start + V, ';').?; // name ≥ 32 B (rare)
}

inline fn SemiReversedIdx(line: []const u8) usize { // TAIL: assume known EOL
    const n = @min(line.len, V);
    var buf: [V]u8 = @splat(0);
    @memcpy(buf[(V - n)..], line[(line.len - n)..]);
    const _mm: @Vector(V, u8) = buf;

    const semicol: @Vector(V, u8) = @splat(';');

    const mask: std.meta.Int(.unsigned, V) = @bitCast(_mm == semicol);
    return line.len + @as(usize, @ctz(mask)) - V; //ctz count backward
}

inline fn NLIdx(buf: []const u8, pos: usize) usize {
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

inline fn worker(
    arena: std.mem.Allocator,
    buf: []const u8,
    out: *Table,
) !void {

    // HASH
    var stations: Table = try Table.init(arena);

    var start: usize = 0;
    const fast_end = if (buf.len > 128) buf.len - 128 else 0;

    // BODY
    while (start < fast_end) {
        const sep = SemiIdx(buf, start);
        const len = sep - start;
        const key = buf.ptr + start;
        const vec = std.mem.readInt(u64, buf.ptr[sep + 1 ..][0..8], .little);
        const p = parseDataPoint(vec);

        stations.record(key, len, Table.prefixFast(key, len), p.temp);
        start = sep + 1 + p.len;
    }

    // TAIL
    while (start < buf.len) {
        const nl = NLIdx(buf, start);
        defer start = nl + 1;

        const line = buf[start..nl];
        const sep = SemiReversedIdx(line);
        const key = line.ptr;
        const temp = ParseTenths(line[sep + 1 ..]);

        stations.record(key, sep, Table.prefixSafe(key, sep), temp);
    }
    out.* = stations;
}

// line is always []u8;-?d?.d\n
// merykitty's solution
const MAGIC_MULTIPLIER: u64 = 100 * 0x1000000 + 10 * 0x10000 + 1; // 0x640A0001
inline fn parseDataPoint(vec: u64) struct {
    temp: i32,
    len: usize,
} {
    const negated = ~vec;
    const sign: i64 = @as(i64, @bitCast(negated << 59)) >> 63; // byte 1 is `-`(0010 1101) || `0-9`(0011 xxxx)
                                                               // bit 4: differenciator
                                                               // ~vec: because negative is represented as activated bit (see it as `sign = ~(vec[4]);`)
                                                               // `>>63` is arithmetic so it @splat(bit_sign)
    const sign_u: u64 = @bitCast(sign); // digits:0x00.. (which act as positive); `-`:0xFF..
    const without_sign = vec & ~(sign_u & 0xFF); // if(pos) {0x00.. ->& 0x00.. ->~ 0xFF.. ->& full vec}
                                                      // else {0xFF.. ->& 0x00..FF ->~ 0xFF..00 ->& vec except *LE* byte(`-`)}
    const dot: u6 = @intCast(@ctz(negated & 0x10101000)); //detect dot, only byte 1, 2 or 3 (x.x, -x.x|xx.x, -xx.x)
                                                          //0x10101000: check {bit 12 ([1][4]), bit 20 ([2][4]) and bit 28 ([3][4])}
    const aligned = without_sign << @intCast(28 - @as(u32, dot)); // 12|20|28 - 28 = 16|8|0 -> shift to place dot at byte 3 (to handle xx.x and x.xx agnostically)
    const digits = aligned & 0x0F000F0F00; // take only the low-nibble of digits byte only
                                                // because 0-9 in ASCII is `0011 xxxx`, where xxxx is the digit
                                                // `-12.4` -> `124`
    const abs: i64 = @intCast(((digits *% MAGIC_MULTIPLIER) >> 32) & 0x3FF); //MAGIC_MULTIPLIER:
                                                                             //         100 * 0x1000000:  T + 2^8     (1byte)
                                                                             //       + 10 * 0x10000:     U + 2^16    (2bytes)
                                                                             //       + 1:                F + 2^32    (4bytes)
                                                                             //     MAGIC is here to make T, U and F meet at F place
                                                                             //       
                                                                             // multiply creates junk
                                                                             // our value is somewhere in the middle bits
                                                                             // value e[0;999] -> u10(1024)
                                                                             // since aligned dot at byte 3 (big endian side) we have a u64 with top half occupied
                                                                             // >>32 shift value from top to bottom half, then 0x3FF(11 1111 1111; 10bit) select the value from it
    return .{ .temp = @intCast((abs ^ sign) - sign), .len = (dot >> 3) + 3 };
}

pub fn flags(args: anytype, arena: std.mem.Allocator) !struct { //TODO:find iterator type
    csv: []const u8,
    print: []const u8,
    threads: u32,
} {
    var it = args;
    _ = it.next();
    const arg = it.next() orelse "M";
    const csv_size = if (arg.len > 0 and arg[0] == 'M') "100M" else "1B";
    const csv = try std.fmt.allocPrint(arena, "../data/DB_{s}.txt", .{csv_size});
    const print = it.next() orelse "";
    const threads_arg = it.next() orelse "8";
    const threads = try std.fmt.parseInt(u32, threads_arg, 10);

    return .{
        .csv = csv,
        .print = print,
        .threads = threads,
    };
}

pub fn main(init: std.process.Init) !void {
    // FLAGS
    const args = try flags(init.minimal.args.iterate(), init.arena.allocator());

    // FILE
    const file = try std.Io.Dir.cwd().openFile(init.io, args.csv, .{});
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

    const results = try init.arena.allocator().alloc(Table, args.threads);
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
    var stations: Table = try .init(init.arena.allocator());
    for (results) |tlb| {
        for (tlb.slots) |s| {
            if (s.pword_len != 0) stations.fuse(s);
        }
    }

    // PRINT
    if (std.mem.eql(u8, args.print, "p")) {
        var name: []const u8 = undefined;
        var count: i32 = 0;
        var sum: i64 = 0;
        var min: i32 = std.math.maxInt(i32);
        var max: i32 = std.math.minInt(i32);
        var probe_total: u64 = 0;
        var probe_max: u64 = 0;
        var lookup_count: u64 = 0;
        for (stations.slots) |s| {
            if (s.pword_len == 0) continue;
            name = s.pword[0..s.pword_len];
            count = s.count;
            sum = s.sum;
            min = @min(min, s.min);
            max = @max(max, s.max);
            probe_total+= s.probe_total;
            probe_max = @max(s.probe_max, probe_max);
            lookup_count += s.lookup_count;
        }
        const avg: f64 = if (count != 0)
            (@as(f64, @floatFromInt(sum))/10.0)/count
        else
            0.0;

        const min_f: f64 = @as(f64, @floatFromInt(min)) / 10.0;
        const max_f: f64 = @as(f64, @floatFromInt(max)) / 10.0;

        std.debug.print(
        "[{s}]: avg={d:.1} min={d:.1} max={d:.1}\n",
            .{ name, avg, min_f, max_f },

        );
        std.debug.print(
            "probe_total={d}, probe_max={d}, lookup_count={d}\n",
            .{probe_total, probe_max, lookup_count},
        );

    }
}
