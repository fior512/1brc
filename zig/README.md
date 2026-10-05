  ### Zig

  **v1 (6949426)** Textbook:
  - Single SIMD vector (`@Vector(32, u8)`) over the line tail to find `;` (line is >100bytes)
  - Additive avg: `avg = (new + avg) / count`
  - `std.StringHashMapUnmanaged`
  - `f16` for min, avg, max
```zig
  min    4550.00
  median 4580.00
  avg    4592.22
  sd     35.98
  max    4660.00
```


  - fminf + fmaxf: 9.8% of samples, libcalls instead of inline instructions.
  - Hash lookup chain Wyhash + mem.eql + findScalarPos: 3.5 + 4.3 + 4.9 = 12.7%.
  - peekDelimiterInclusive + findScalarPos: 9.6% for the takeDelimiter('\n') line split
  - Branch-miss rate 2.0% (172M misses, about 1.7 per row). Probably the semicolon
  - L1d miss 3.6% (558M, about 5.6 per row). It is high for a hot-loop-only workload
