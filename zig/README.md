# Zig

Run from `zig/`: `zig build -Doptimize=ReleaseFast -Dcpu=native` then `sudo goset -n 8 -cgroup -fence -steer --interval 1 -- ./zig-out/bin/_1brc B "" 8`
## Summary (ms, 100M rows)
| ver | commit | med | sd | min | max | vs prev | vs v1 | aspects |
|---|---|---|---|---|---|---|---|---|
| v1 | 6949426 | 4580.00 | 35.98 | 4550.00 | 4660.00 | - | - | textbook |
| v2 | 7f14c3f | 3995.00 | 48.41 | 3940.00 | 4060.00 | -12.8% | -12.8% | mmap + SIMD `\n` |
| v3 | e038fed | 2895.00 | 31.00 | 2830.00 | 2920.00 | -27.5% | -36.8% | fixed-point parse |
| v4 | 95f2118 | 1530.00 | 12.65 | 1500.00 | 1540.00 | -47.2% | -66.6% | merykitty's SWAR |
| v5 | 362acff | 391.74 | 9.14 | 387.31 | 419.07 | -74.40% | -91.45% | threadpool |
| v6 | 94cc335 | 253.25 | 0.89 | 251.49 | 254.21 | -35.35% | -94.47% | AoS linear probing |
| v7 | | 223.06 | 0.49 | 221.81 | 223.38 | -11.57% | -95.12% | fast-path eqlKey |


## v1: Textbook
**Change**
- Single SIMD vector (`@Vector(32, u8)`) over the line tail to find `;` (line is >100 bytes)
- Additive avg: `avg = (new + avg) / count`
- `std.StringHashMapUnmanaged`
- `f16` for min, avg, max

**Profile**
- `fminf` + `fmaxf`: 9.8% of samples, libcalls instead of inline instructions
- Hash lookup chain `Wyhash` + `mem.eql` + `findScalarPos`: 3.5 + 4.3 + 4.9 = 12.7%
- `peekDelimiterInclusive` + `findScalarPos`: 9.6% for the `takeDelimiter('\n')` line split
- Branch-miss rate 2.0% (172M misses, about 1.7 per row). Probably the semicolon
- L1d miss 3.6% (558M, about 5.6 per row). It is high for a hot-loop-only workload

## v2: MMAP + SIMD newline
**Change**
- `mmap` (`MAP_POPULATE`) replaces the buffered `Io.Reader`
- SIMD `\n` scan (`@Vector(V, u8)`) over the mapped buffer and scalar tail at EOF with `std.mem.indexOfScalarPos`
- Average on output demand, instead of incremental (now just a sum and count)

## v3: Fixed-point parse
**Change**
- `ParseTenthsFast` (`src/main.zig:22`): temperature as integer tenths (`-12.3` -> `-123`), no `parseFloat(f16)`
- Branchless sign: `(value ^ -is_negative) + is_negative`
- `min`/`max`/`sum` as `i32`/`i32`/`i64`, average = `sum / count / 10` at print time
- Data path now `../data/DB_*.txt` (run from `zig/`)

**Profile** (`perf record -F 2000`, 100M rows, 4633 samples)
- `mem.eql` 13.0%: key compare on every hash hit
- `memcpyFast` 9.1%: runtime-length `@memcpy` in `SemiReversedIdx` (size dispatch `cmp $0x3f`)
- `Wyhash.hash` 8.9%: generic hash for short names
- Instructions 26.7G (267 per row, was 561); IPC 1.8; branch-miss rate 4.0% (135M, 1.35 per row); L1d miss 4.8% (479M, 4.8 per row)


## v4: Merykitty's SWAR
**Change**
- `SemiIdx` (`src/main.zig`): SIMD `;` search with a direct vector load (no `memcpy`); scalar `indexOfScalarPos` fallback for names >= 32 B
- `parseDataPoint` (`src/main.zig`): SWAR temperature parse from one `u64` load; sign, dot position and digits decoded with bit masks and a magic multiply, no per-byte branches

**Profile** (ReleaseFast, `perf record`)
- `HashMapUnmanaged.getOrPut`: 50.0%
- `mem.eql`: 18.9%
- `Wyhash.hash`: 12.1%
- `start.posixCallMainAndExit` (main body, inlined SWAR parse + `SemiIdx`): 14.8%
- Kernel (page faults from mmap): ~2.4%
- Hash map lookup + key compare: ~81% of samples


## v5: Threadpool
**Change**
- `std.Thread.spawn` pool with arena, one hashmap per thread, merging hashmap at once with `Entry.Fuse()`
- Custom `Ctx` hash/eql replaces std `StringHashMapUnmanaged`/Wyhash for `HashMapUnmanaged()`. hash = first 8 bytes as LE u64 (zero-padded for short keys) `^` len, multiply `0x9E3779B97F4A7C15`, fold high bits down for the map's low-bit index
- `getOrPutAssumeCapacity` after `ensureTotalCapacity(arena, 1 << 15)`: hot loop does no growth/rehash; keys duped into per-thread arena
- `flags()` parse binary arguments for readability

**Profile**
- `HashMapUnmanaged.getOrPutAssumeCapacityAdapted`: 51.8%
- `Thread.callFn`: 30.3%
- `mem.eql`: 14.3%, key compare on every hash hit
- mmap page faults: ~1.2% (`follow_page_pte` + `__get_user_pages` + `__pte_offset_map_lock`)
- Hash map lookup + key compare: ~66% of samples

## v6: AoS linear probing
**Change**
- `Table` replaces `HashMapUnmanaged`: `[32768]Slot` AoS, 64B aligned, linear probing, fixed size(no alloc; which was in hotpath due to dupe and hashmap size).
- `Slot.pword` points in mmap with fast hash from v5
- `eqlKey` with 3 sizes (>=16, >=8, >=4) to let it vectorize (memcpy, @vector)

**Profile**
- `parseDataPoint` 29.6%, `eqlKey` 29.5%, stats update 18.2% (diagnostics 6.5% of it), `SemiIdx` 11.2%, hash 8.5%
- Per row: 99.8 instructions, IPC 1.19, 0.86 branch misses, 1.36 L1d misses
- Top-down: SMT contention 32.3% (goset's strategy), backend memory 28.5%, mispredicts 7.0%
- `llvm-mca` ideal 26.7 cycles per row vs 83.6 measured


## v7: Fast Path eqlKeyTail
**Change**
- new `eqlKeyTail` to have a branchless alternative to `eqlKey` when possible, switching with `switch()`
