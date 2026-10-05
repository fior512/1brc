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
