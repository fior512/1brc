//TODO:
// - Other probing/linked list strategies
// - precompute slots owner with overfitted hash over keyset for no hashing
// - pinmemory trick without hashing nor collisions??
// - u64 -> u128 key
//

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

fn x86_64_tsc() u64 {
    return asm volatile(
        \\ rdtsc
        \\ shl $32, %%rdx
        \\ or %%rdx, %%rax
        : [ret] "={rax}" (-> u64)
        :
        : .{ .rdx = true }
    );
}

const DEBUG = false; // probe telemetry
const TSC_GHZ = 4.7; // 7600X
const V = 32; // bytes (AVX)
const LANES = 2; //v8:  1: 64.3B cycles; 2: 49.7B cycles; 3: 49.6B; 4: 58.8B cycles
const TABLE_BITS = 17; //v9: 15: 950ms; 17: 900ms
const TABLE_SLOTS = 1 << TABLE_BITS;

const STATION_NAMES= @embedFile("stations"); // addAnonymousImport() in build.zig
const PHF_BUCKET_BITS = 10;
const PHF_BUCKETS = 1 << PHF_BUCKET_BITS;
const STATION_COUNT = blk: {
    @setEvalBranchQuota(1_000_000);
    break :blk std.mem.count(u8, STATION_NAMES, "\n");
};

const Phf = struct {
    mult: u64 = 0x63CBE1E459320DD7, //7191089600892374487
    shifts: [PHF_BUCKETS]u16 = @splat(0),
};


const phf: Phf = .{};
fn buildPhf() Phf {
    @setEvalBranchQuota(2_000_000_000); // increase default limits


    // chars to key
    var keys: [STATION_COUNT]u64 = undefined; // out
    var lines = std.mem.tokenizeScalar(u8, STATION_NAMES, '\n'); //split rows
    var n: usize = 0;
    while (lines.next()) |name| : (n+=1) { // contains only the city
        var word: u64 = 0;
        for (name[0..@min(name.len, 8)], 0..) |char, idx| { // 8 first bytes
            word |= @as(u64, char) << @intCast(8*idx); // place the char to its position in u64
        }
        keys[n] = word ^ name.len; // 2 cities with same prefix lands with higher P differently with len mixup
    }

    // naive random search
    var seed: u64 = 7;
    while (true) { // splitmix64 (same speed as xoroshiro128+ but more stable)
        seed +%= 0x9E3779B97F4A7C15; 
        var z = seed;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        const mult = (z ^ (z >> 31)) | 1;
        if (placeBuckets(&keys, mult)) |shifts| return .{ .mult = mult, .shifts = shifts };
    }
}

fn placeBuckets(keys: *const [STATION_COUNT]u64, mult: u64) ?[PHF_BUCKETS]u16 { // return Phf.shifts
    // Goal is to obtain one slot per key, but nearly impossible to treat
    //      to do so, we use buckets as "cluster" of keys that are "close" to each others
    //          from this cluster we can then use a single parameter (shift) to finetune them to avoid collisions
    //          single mult, one shift per bucket (shift lookup-table with cluster to compress it)
    //
    
    const none = std.math.maxInt(u32);
    
    var bucket_heads: [PHF_BUCKETS]u32 = @splat(none); // first key_index of the bucket ("owner" of the bucket)
    var next_in_bucket: [STATION_COUNT]u32 = undefined; // linked list dangling from `bucket_heads` (for every key_index, associate to an other key_index as "owner")
    var bucket_sizes: [PHF_BUCKETS]u16 = @splat(0);
    var largest: u16 = 0;

    // Test `mult` trial (caller)
    for (keys, 0..) |key, idx| {
        const bucket = (key *% mult) >> (64 - PHF_BUCKET_BITS); // bucket slot
        next_in_bucket[idx] = bucket_heads[bucket]; // push_front()
        bucket_heads[bucket] = @intCast(idx); // Iter(key_index) -> Key Owner
        bucket_sizes[bucket] += 1; // bucket size
        largest = @max(largest, bucket_sizes[bucket]);
    }

    // Evaluate
    var used: [TABLE_SLOTS]bool = @splat(false);
    var shifts: [PHF_BUCKETS]u16 = @splat(0);
    var target_size: u16 = largest; // largest first
    while (target_size > 0) : (target_size -= 1) {
        for (0..PHF_BUCKETS) |bucket| {
            if (bucket_sizes[bucket] != target_size) continue;

            var group_offsets: [256]usize = undefined; // one entry per distinct key of the bucket
            var group_sizes: [256]usize = undefined;
            var group_keys: [256]u64 = undefined;
            var group_count: usize = 0;
            var key_index = bucket_heads[bucket]; 

            while (key_index != none) : (key_index = next_in_bucket[key_index]) { // unroll the bucket
                const hash = keys[key_index] *% mult;
                const offset: usize = @intCast((hash >> (64 - PHF_BUCKET_BITS - TABLE_BITS)) & (TABLE_SLOTS - 1));
                var same_key = false;
                for (0..group_count) |group| {
                    if (group_keys[group] == keys[key_index]) {
                        group_sizes[group] += 1;
                        same_key = true;
                    } else if (group_offsets[group] == offset) {
                        return null; // no shift can separate these two, refute the `mult` trial
                    }
                }
                if (!same_key) {
                    if (group_count == group_offsets.len) return null;
                    group_keys[group_count] = keys[key_index];
                    group_offsets[group_count] = offset;
                    group_sizes[group_count] = 1;
                    group_count += 1;
                }   
            }
              
            var shift: usize = 0;
            place: while (shift < TABLE_SLOTS and shift <= std.math.maxInt(u16)) : (shift += 1) {
                var marked: [256]usize = undefined;
                var marked_count: usize = 0;
                var fits = true;
                check: for (0..group_count) |group| {
                    for (0..group_sizes[group]) |j| {
                        const slot = (group_offsets[group] + shift + j) & (TABLE_SLOTS - 1);
                        if (used[slot] or marked_count == marked.len) {
                            fits = false;
                            break :check;
                        }
                        used[slot] = true;
                        marked[marked_count] = slot;
                        marked_count += 1;
                    }
                }
                if (fits) {
                    shifts[bucket] = @intCast(shift);
                    break :place;
                }   
                for (marked[0..marked_count]) |slot| used[slot] = false;
            } else return null;
        }   
    }
    return shifts;
}

const Stats = if (DEBUG) struct {
    probe_total: u64 = 0,
    probe_max: u64 = 0,
    lookup_count: u64 = 0,
} else struct {};

const Slot = struct {
    pword: [*]const u8 align(64), // -50ms
    pword_len: u64,

    prefix: u64,
    suffix: u64,

    sum: i64,
    count: i32,
    min: i32,
    max: i32,
    
    stats: Stats = .{},
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
        // .@"64" is an enum litteral item for alignement size, @ is here to allow names starting with number
        @memset(std.mem.sliceAsBytes(slots), 0);
        return .{ .slots = slots };
    }

    inline fn hash(word: u64, len: usize) u64 {
        //(1+ sqrt(5))/2 = @as(u64, 1.6180339887)
        return (word ^ len) *% phf.mult; //0x9E3779B97F4A7C15; // custom hash over key (comptime)

        // both official datasets (1B and 10k) doesn't need custom hash() because only 413 city names exist
        //      additional names are slice-mix from existing ones, so `word ^ len` is carrying the collisions mitigation.
        //  I started this adventure with a synthetic datasets (9674 city names) and (w^l)*%0x9E3779B97F4A7C15 leading to +16k collisions
        //      So custom hashing was necessary for me, i now use my custom version without the shifts because it still handles better the official 1B.
        //
        //

        // TABLE_BITS = 17
        // (word ^ len) *% MAGIC
        // 1B
        //      0x9E3779B97F4A7C15: probe_total=4968, probe_max=2, lookup_count=4956; 12 collisions
        //      0x63CBE1E459320DD7: probe_total=4956, probe_max=1, lookup_count=4956;  0 collisions
        //
        // 10k
        //      0x9E3779B97F4A7C15: probe_total=124764, probe_max=4, lookup_count=120000; 4764 collisions
        //      0x63CBE1E459320DD7: probe_total=124548, probe_max=4, lookup_count=120000; 4548 collisions
        //
        //
        //  collisions are summed, so avg: x/threads ~= 400 per threads; 95% are fine
        //  i can make it drop to 0 by adding shift, but not worth the home() logic per hash
        //
        //  0x63CBE1E459320DD7 have been generated for the synthetic dataset, not the official

    }

    // Phf.mult is carrying the hashing, shifts aren't necessary in this scenario.
    // This is the function i am supposed to use if Phf.mult was overfitted
    //
    // inline fn home(word: u64, len: usize) usize {
    //     const h = hash(word, len);
    //     const bucket = h >> (64 - PHF_BUCKET_BITS);
    //     const offset = (h >> (64 - PHF_BUCKET_BITS - TABLE_BITS)) & (TABLE_SLOTS - 1);
    //     return @intCast((offset + phf.shifts[bucket]) & (TABLE_SLOTS - 1));
    // }


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


        var i: usize = @intCast(hash(word, len) >> (64 - TABLE_BITS)); //home(word, len); // logical slot in AoS

        var probes: u64 = 0;
        while (true) : (i = (i + 1) & (TABLE_SLOTS - 1)) { // linear probing if occupied
            probes += 1;
            const slot = &self.slots[i];
            if (slot.pword_len == len and slot.prefix == word and switch (len) {
                0...8 => true,
                9...16 => slot.suffix == suffix(pword, len), // branchless
                else => slot.suffix == suffix(pword, len) and eqlKey(slot.pword, pword, len),
            }) {
                if (comptime DEBUG) {
                    slot.stats.probe_total += probes;
                    slot.stats.probe_max = @max(slot.stats.probe_max, probes);
                    slot.stats.lookup_count += 1;
                }
                return slot;
            } // found
            if (slot.pword_len == 0) { // empty slot (real or probing) || MAQAO
                slot.* = .{
                    .pword = pword,
                    .pword_len = @intCast(len),

                    .prefix = word,
                    .suffix = if (len>8) suffix(pword, len) else 0, 
                    .sum = 0,
                    .count = 0,
                    .min = std.math.maxInt(i32),
                    .max = std.math.minInt(i32),
                    
                };
                if (comptime DEBUG) {
                    slot.stats.probe_total = probes;
                    slot.stats.probe_max = probes;
                    slot.stats.lookup_count = 1;
                }
                return slot;
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
            else (@as(u64, 1) << @intCast(8 * len)) - 1; // or 0x100-1=0xFF..
        return word & glight;
    }

    inline fn suffix(pword: [*]const u8, len: usize) u64 {
        return std.mem.readInt(u64, pword[len-8..][0..8], .little);
    }

    inline fn record(self: *Table, pword: [*]const u8, len: usize, word: u64, temp: i32) void {
        //nasty API due to prefix* optimization (pword U word)
        const slot = self.find(pword, len, word);
        slot.count += 1;
        slot.min = @min(slot.min, temp);
        slot.sum += temp;
        slot.max = @max(slot.max, temp);
    }

    inline fn fuse(self: *Table, other: Slot) void {
        const slot = self.find(other.pword, other.pword_len, prefixSafe(other.pword, other.pword_len));
        slot.count += other.count;
        slot.min = @min(slot.min, other.min);
        slot.sum += other.sum;
        slot.max = @max(slot.max, other.max);
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

inline fn lineStartAtOrAfter(buf: []const u8, pos: usize) usize {
    if (pos == 0 or pos >= buf.len) return @min(pos, buf.len);
    return @min(NLIdx(buf, pos - 1) + 1, buf.len);
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

inline fn ParserTail(stations: *Table, buf: []const u8, start0: usize) void {
    var start = start0;
    const fast_end = if (buf.len > 128) buf.len - 128 else 0;

    // BODY
    while (start < fast_end) {
        const sep = SemiIdx(buf, start);
        const len = sep - start;
        const pword = buf.ptr + start;
        const vec = std.mem.readInt(u64, buf.ptr[sep + 1 ..][0..8], .little);
        const p = parseDataPoint(vec);

        stations.record(pword, len, Table.prefixFast(pword, len), p.temp);
        start = sep + 1 + p.len;
    }

    // TAIL
    while (start < buf.len) {
        const nl = NLIdx(buf, start);
        defer start = nl + 1;

        const line = buf[start..nl];
        const sep = SemiReversedIdx(line);
        const pword = line.ptr;
        const temp = ParseTenths(line[sep + 1 ..]);

        stations.record(pword, sep, Table.prefixSafe(pword, sep), temp);
    }

}

inline fn allBelow(pos: [LANES]usize, limit: [LANES]usize) bool { // eww
    var state = true;
    inline for (0..LANES) |l| state = (state and pos[l] < limit[l]);
    return state;
}


inline fn worker(
    arena: std.mem.Allocator,
    buf: []const u8,
    out: *Table,
    busy_tsc: *u64,
) !void {
    const t_begin = x86_64_tsc(); // here to produce threads imbalance
    defer busy_tsc.* = x86_64_tsc() - t_begin;

    // HASH
    var stations: Table = try Table.init(arena);
    
    var sub: [LANES][]const u8 = undefined; // LANES sub-slices
    var a: usize = 0;
    for (0..LANES) |l| { // cut the thread' slice by LANES
        const b = 
            if (l == LANES-1) buf.len // end of worker slice
            else lineStartAtOrAfter(buf, buf.len/LANES * (l+1));

        sub[l] = buf[a..b];
        a = b;
    }

    var pos: [LANES]usize = @splat(0); // set 0 to all lanes
    var limit: [LANES]usize = undefined;
    inline for (0..LANES) |l| limit[l] = if (sub[l].len > 128) sub[l].len - 128 else 0;

    while (allBelow(pos, limit)) {
        var pword: [LANES][*]const u8 = undefined;
        var len: [LANES]usize = undefined;
        var word: [LANES]u64 = undefined;
        var temp: [LANES]i32 = undefined;

        inline for (0..LANES) |l| { 
            const slot = sub[l];
            const sep = SemiIdx(slot, pos[l]);
            const p = parseDataPoint(std.mem.readInt(u64, slot.ptr[sep+1..][0..8], .little));

            pword[l] = slot.ptr + pos[l];
            len[l] = sep - pos[l];
            word[l] = Table.prefixFast(pword[l], len[l]);
            temp[l] = p.temp;
            pos[l] = sep+1+p.len;

            @prefetch( // Prefetch slot
                &stations.slots[Table.hash(word[l], len[l]) >> (64 - TABLE_BITS)], 
                .{ .rw = .read, .locality = 3, .cache = .data},
            ); // hash is fused by LLVM, no redundant hashing with (below)record() -> find() -> hash()
        }
        // prefetch logical slot for each LANEs chunk[i]
        // update AoS
        // ++i

        inline for (0..LANES) |l| stations.record(pword[l], len[l], word[l], temp[l]); // AoS boost via prefetched
    }

    inline for (0..LANES) |l| ParserTail(&stations, sub[l], pos[l]); // tail
    out.* = stations;
}

// line is always []u8;?-?dd.d\n
// merykitty'slot solution
const MAGIC_MULTIPLIER: u64 = 100 * 0x1000000 + 10 * 0x10000 + 1; // 0x640A0001
inline fn parseDataPoint(vec: u64) struct {
    temp: i32,
    len: usize,
} {
    const negated = ~vec;
    const sign: i64 = @as(i64, @bitCast(negated << 59)) >> 63; // byte 1 is `-`(0010_1101) || `0-9`(0011_xxxx)
                                                               // bit 4: differenciator
                                                               // ~vec: because negative is represented as activated bit (see it as `sign = ~(vec[4]);`)
                                                               // `>>63` is arithmetic so it @splat(bit_sign)
    const sign_u: u64 = @bitCast(sign); // digits:0x00.. (which act as positive); `-`:0xFF..
    const without_sign = vec & ~(sign_u & 0xFF); // if(pos) {0x00.. ->& 0x00.. ->~ 0xFF.. ->& full vec}
                                                      // else {0xFF.. ->& 0x00..FF ->~ 0xFF..00 ->& vec except *LE* byte(`-`)}
    const dot: u6 = @intCast(@ctz(negated & 0x10101000)); //detect dot, only byte 1, 2 or 3 (x.x, -x.x|xx.x, -xx.x)
                                                          //0x10101000: check {bit 12 ([1][4]), bit 20 ([2][4]) and bit 28 ([3][4])}
                                                          //same as for '-' vs '0-9', bit differenciator is bit 4 ("." 0010_1110)
    const aligned = without_sign << @intCast(28 - @as(u32, dot)); // 12|20|28 - 28 = 16|8|0 -> shift to place dot at byte 3 (to handle xx.x and x.xx agnostically)
    const digits= aligned & 0x0F000F0F00; // take only the low-nibble of digits byte only
                                                // because 0-9 in ASCII is `0011_xxxx`, where xxxx is the digit
                                                // `-12.4` -> `124`
    const real: i64 = @intCast(((digits *% MAGIC_MULTIPLIER) >> 32) & 0x3FF); //MAGIC_MULTIPLIER:
                                                                             //         100 * 0x1000000:  T + 2^8     (1byte)
                                                                             //       + 10 * 0x10000:     U + 2^16    (2bytes)
                                                                             //       + 1:                F + 2^32    (4bytes)
                                                                             //     MAGIC is here to make T, U and F meet at F place
                                                                             //       
                                                                             // multiply creates junk
                                                                             // our value is somewhere in the middle bits
                                                                             // value group[0;999] -> u10(1024)
                                                                             // since aligned dot at byte 3 (big endian side) we have a u64 with top half occupied
                                                                             // >>32 shift value from top to bottom half, then 0x3FF(11 1111 1111; 10bit) select the value from it
    return .{ .temp = @intCast((real ^ sign) - sign), .len = (dot >> 3) + 3 };
}

pub fn flags(args: std.process.Args.Iterator) !struct {
    csv: []const u8,
    print: []const u8,
    threads: u32,
} {
    var it = args;
    _ = it.next();
    const csv = it.next().?; // path
    const threads_arg = it.next() orelse "8";
    const print = it.next() orelse "";
    const threads = try std.fmt.parseInt(u32, threads_arg, 10);

    return .{
        .csv = csv,
        .print = print,
        .threads = threads,
    };
}

fn forkWorker() !i32 {
    // HACK: push munmap latency out of the process latency
    // real task would have been a infra, throughput doesn't take exit latency in count
    var fds: [2]i32 = undefined;
    if (std.os.linux.errno(std.os.linux.pipe(&fds)) != .SUCCESS) return error.PipeFailed;
    const pid = std.os.linux.fork();
    if (std.os.linux.errno(pid) != .SUCCESS) return error.ForkFailed;
    if (pid == 0) return fds[1]; // worker
  
    _ = std.os.linux.close(fds[1]); // a dead worker gives EOF instead of hanging the parent
    var done: [1]u8 = undefined;
    const n = std.os.linux.read(fds[0], &done, 1);
    std.os.linux.exit_group(if (n == 1) 0 else 1);
}

fn tscToMs(tsc: u64) f64 {
    return @as(f64, @floatFromInt(tsc)) / TSC_GHZ / 1e6;
}

// marks: TSC at start, setup, parse, merge, print
fn printMetrics(marks: [5]u64, busy_tsc: []u64, rows: u64, size: u64) void {
    const total = marks[4] - marks[0];
    const total_tsc: f64 = @floatFromInt(total);
    const rows_f: f64 = @floatFromInt(rows);
    const threads: f64 = @floatFromInt(busy_tsc.len);

    std.mem.sort(u64, busy_tsc, {}, std.sort.asc(u64)); // reorders the caller's slice
    const count = busy_tsc.len;
    const busy_max: f64 = @floatFromInt(busy_tsc[count - 1]);
    const busy_median = (@as(f64, @floatFromInt(busy_tsc[(count - 1) / 2])) +
        @as(f64, @floatFromInt(busy_tsc[count / 2]))) / 2;

    std.debug.print(
        "\ntotal={d:.1}ms   setup={d:.1}ms   parse={d:.1}ms   merge={d:.1}ms   print={d:.1}ms\n",
        .{
            tscToMs(total),
            tscToMs(marks[1] - marks[0]),
            tscToMs(marks[2] - marks[1]),
            tscToMs(marks[3] - marks[2]),
            tscToMs(marks[4] - marks[3]),
        },
    );
    std.debug.print(
        "rows={d}   {d:.2} tsc/line   {d:.2} thread-ns/line   {d:.1}% imbalance   {d:.2} GB/s\n",
        .{
            rows,
            total_tsc / rows_f,
            tscToMs(total) * 1e6 * threads / rows_f,
            (busy_max / busy_median - 1) * 100,
            @as(f64, @floatFromInt(size)) * TSC_GHZ / total_tsc,
        },
    );
}

pub fn main(init: std.process.Init) !void {
    const t1 = x86_64_tsc();
    const done_fd = try forkWorker();

    // FLAGS
    const args = try flags(init.minimal.args.iterate());

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
        .{ .TYPE = .PRIVATE },
        file.handle,
        0,
    );
    //defer std.posix.munmap(whole);

    const t_setup = x86_64_tsc();

    // Multi HOTPATH
    const handles = try init.arena.allocator().alloc(std.Thread, args.threads);
    const busy_tsc = try init.arena.allocator().alloc(u64, args.threads);

    const arenas = try init.arena.allocator().alloc(std.heap.ArenaAllocator, args.threads);
    for (arenas) |*a| a.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer for (arenas) |*a| a.deinit();

    const results = try init.arena.allocator().alloc(Table, args.threads);
    for (0..args.threads) |t| {
        const start = lineStartAtOrAfter(whole, chunk * t);
        const end = if (t == args.threads - 1) size else lineStartAtOrAfter(whole, chunk * (t + 1));

        handles[t] = try std.Thread.spawn(
            .{},
            worker,
            .{ arenas[t].allocator(), whole[start..end], &results[t], &busy_tsc[t] },
        );
    }
    for (handles) |h| h.join();
    const t_parse = x86_64_tsc();

    // MERGE
    var stations: Table = try .init(init.arena.allocator());
    var rows: u64 = 0;
    for (results) |tlb| {
        for (tlb.slots) |slot| {
            if (slot.pword_len != 0) {
                stations.fuse(slot);
                rows += @intCast(slot.count);
            }
        }
    }
    const t_merge = x86_64_tsc();

    // PRINT
    if (std.mem.eql(u8, args.print, "p")) {
        var name: []const u8 = undefined;
        var count: i32 = 0;
        var sum: i64 = 0;
        var min: i32 = std.math.maxInt(i32);
        var max: i32 = std.math.minInt(i32);
        var stats: Stats = .{};

        for (stations.slots) |slot| {
            if (slot.pword_len == 0) continue;
            name = slot.pword[0..slot.pword_len];
            count = slot.count;
            sum = slot.sum;
            min = @min(min, slot.min);
            max = @max(max, slot.max);
            
            if (comptime DEBUG) {
                stats.probe_total+= slot.stats.probe_total;
                stats.probe_max = @max(stats.probe_max, slot.stats.probe_max);
                stats.lookup_count += slot.stats.lookup_count;       
            }
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

        if (comptime DEBUG) {
            std.debug.print(
                "probe_total={d}, probe_max={d}, lookup_count={d}\n",
                .{stats.probe_total, stats.probe_max, stats.lookup_count},
            );
        }

    }
    const t_print = x86_64_tsc();
    printMetrics(.{ t1, t_setup, t_parse, t_merge, t_print }, busy_tsc, rows, size);
    
    _ = std.os.linux.close(1);
    _ = std.os.linux.close(2);
    _ = std.os.linux.write(done_fd, "x", 1);
}
