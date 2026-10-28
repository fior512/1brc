# 1BRC

### Rules

- No `stdout` of produced stats
- Machine state: `watchcub bench --pinfreq=off --cstate=keep`
- Run: `sudo goset -n 1 -cgroup -steer -fence -interval 5`
- Iterations: **>10**
- Multithreading: 8 threads

### Perfomances (ms; 100M rows)
| lang | med | sd | min | max | 1B | link |
|---|---|---|---|---|---|---|
| **Zig** | 253.25 | 0.89 | 251.49 | 254.21 | 2.429s | [Zig](zig/README.md) |


### Outputs
**ZIG**

```zig
----------------- GOSET -----------------
Selection
  cpu  sel  steer  non-steer  core  sibl  isol  numa  nohz  rcu
    8   *       0         24    56     2           0
    2   *      25         32    56     8           0
    7   *       1         22    59     1           0
    1   *       0         37    59     7           0
    4   *       0         67   256    10           0
   10   *       8        189   256     4           0
    6   *       0         21   277     0           0
    0   *       0        256   277     6           0
    5   &       0        126   306    11           0
   11           0        180   306     5           0
    3           4        122   369     9           0
    9         246        247   369     3           0

Telemetry
  cpu  freq min  freq avg  freq max  throttle count  irq steerable  irq non-steerable
  0     2.99GHz   4.73GHz   5.22GHz               0              0                992
  1     2.99GHz   4.75GHz   5.21GHz               0              0                795
  2     2.99GHz   4.77GHz   5.45GHz               0              0                792
  4     2.99GHz   5.12GHz   5.45GHz               0              0              1.02k
  6     2.99GHz   4.75GHz   5.21GHz               0              0                807
  7     2.99GHz   4.75GHz   5.21GHz               0              0                773
  8     2.99GHz   4.77GHz   5.45GHz               0              0                974
  10    2.99GHz   4.77GHz   5.44GHz               0              0                919
  all   2.99GHz   4.80GHz   5.45GHz               0              0              7.08k

Run
  task            sched                  steer
  poll  2416@1ms  ctxsw vol          10  applied         40
  wall    2.429s  ctxsw invol       266  rejected        26
  util      672%  migrations          2  remaining        0
  exit         0  run_delay     7.000μs  drift            0
                                         irqbalance  absent
```

```zig
zig build -Doptimize=ReleaseFast
sudo goset -n 8 -cgroup -steer -fence --interval 1 -- ./zig-out/bin/_1brc B "" 8
```
