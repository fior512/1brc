# Zig

Run from `zig/`: `zig build -Doptimize=ReleaseFast && ./zig-out/bin/_1brc M` (data: `../data/DB_*.txt`)

## Summary (ms, 100M rows)
| ver | commit | med | sd | min | max | vs prev | vs v1 | aspects |
|---|---|---|---|---|---|---|---|---|
| v1 | 6949426 | 4580.00 | 35.98 | 4550.00 | 4660.00 | - | - | textbook |
| v2 | 7f14c3f | 3995.00 | 48.41 | 3940.00 | 4060.00 | -12.8% | -12.8% | mmap + SIMD `\n` |
| v3 | <hash> | 2895.00 | 31.00 | 2830.00 | 2920.00 | -27.5% | -36.8% | fixed-point parse |

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
