# 1BRC

### Rules

- No `stdout` of produced stats
- Run: `sudo goset -n 1 -cgroup -steer -fence -interval 5`
- Iterations: **>10**
- Multithreading: 8 threads

> stop using goset in v10, but keeping 8 threads

### Perfomances (ms; 100M rows)
| lang | med | sd | min | max | 1B(real) | link |
|---|---|---|---|---|---|---|
| **Zig** | 139.25 | 4.37 | 136.50 | 149.80 | 1.307s (0.930s)| [Zig](zig/README.md) | 

> real: sched managed task, 12 threads.

### Comparison (s; 1B rows)
| impl | official 1B| vs me | official 10k 1B | vs me | 1B synthetic | vs Zig |
|---|---|---|---|---|---|---|
| me Zig | 0.738 | | 1.023 | | 0.893 | |
| [lehuyduc](https://github.com/lehuyduc/1brc-simd) C++ | 0.641 | -13.1% | 0.926 | -9.5% | 0.824 | -7.8% |
| [austindonisan](https://github.com/austindonisan/1brc) C | 0.325 | -56.0% | 0.913 | -10.8% | 0.627 | -29.8% |


### Outputs
**synthetic 1B, 8 threads, goset**

```zig
total=1306.2ms   setup=0.1ms   parse=1301.2ms   merge=4.9ms   print=0.0ms
rows=1000000000   6.14 tsc/line   10.45 thread-ns/line   0.5% imbalance   11.58 GB/s


----------------- GOSET -----------------
Selection
  cpu  sel  steer  non-steer  core  sibl  isol  numa  nohz  rcu
    8   *       0          2    60     2           0
    2   *       0         58    60     8           0
    7   *       0         33   101     1           0
    1   *       0         68   101     7           0
    4   *       0         64   266    10           0
   10   *     332        202   266     4           0
    5   *       0         60   394    11           0
   11   *       0        334   394     5           0
    6   &       0         26   459     0           0
    0           0        433   459     6           0
    3           4        299   688     9           0
    9           1        389   688     3           0

Telemetry
  cpu  freq min  freq avg  freq max  throttle count  irq steerable  irq non-steerable
  1     2.99GHz   4.96GHz   5.16GHz               0              0                555
  2     3.23GHz   4.96GHz   5.16GHz               0              0                543
  4     3.77GHz   4.96GHz   5.16GHz               0              0                588
  5     2.99GHz   4.96GHz   5.16GHz               0              0                533
  7     2.99GHz   4.95GHz   5.16GHz               0              0                545
  8     2.99GHz   4.96GHz   5.16GHz               0              0                547
  10    3.79GHz   4.96GHz   5.16GHz               0              0                529
  11    3.31GHz   4.96GHz   5.16GHz               0              0                515
  all   2.99GHz   4.96GHz   5.16GHz               0              0              4.36k

Run
  task            sched             steer
  poll  1301@1ms  ctxsw vol      2  applied         40
  wall    1.307s  ctxsw invol    0  rejected        26
  util        0%  migrations     0  remaining        0
  exit         0  run_delay    0ns  drift            0
                                    irqbalance  absent
```
