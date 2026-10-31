# 1BRC

### Rules

- No `stdout` of produced stats
- Run: `sudo goset -n 1 -cgroup -steer -fence -interval 5`
- Iterations: **>10**
- Multithreading: 8 threads

### Perfomances (ms; 100M rows)
| lang | med | sd | min | max | 1B | link |
|---|---|---|---|---|---|---|
| **Zig** | 223.06 | 0.49 | 221.81 | 223.38 | 2.164s | [Zig](zig/README.md) |


### Outputs
**ZIG**

```zig
----------------- GOSET -----------------
Selection
  cpu  sel  steer  non-steer  core  sibl  isol  numa  nohz  rcu
    7   *       0          0    47     1           0
    1   *       0         47    47     7           0
    2   *       0         42    98     8           0
    8   *       0         56    98     2           0
    3   *       0         52   124     9           0
    9   *       0         72   124     3           0
    0   *       0        120   273     6           0
    6   *       0        153   273     0           0
    4   &       1         76   364    10           0
   10           0        288   364     4           0
    5         250        204   470    11           0
   11           0        266   470     5           0

Telemetry
  cpu  freq min  freq avg  freq max  throttle count  irq steerable  irq non-steerable
  0     2.99GHz   4.76GHz   5.43GHz               0              0                844
  1     2.99GHz   4.73GHz   5.24GHz               0              0                683
  2     2.99GHz   5.10GHz   5.45GHz               0              0                868
  3     2.45GHz   4.77GHz   5.35GHz               0              0                851
  6     2.99GHz   4.72GHz   5.24GHz               0              0                693
  7     2.99GHz   4.72GHz   5.24GHz               0              0                696
  8     2.99GHz   4.71GHz   5.43GHz               0              0                692
  9     2.99GHz   4.72GHz   5.24GHz               0              0                661
  all   2.45GHz   4.78GHz   5.45GHz               0              0              5.99k

Run
  task            sched                   steer
  poll  2147@1ms  ctxsw vol           11  applied         40
  wall    2.164s  ctxsw invol        246  rejected        26
  util      666%  migrations           4  remaining        1
  exit         0  run_delay     49.120μs  drift            0
                                          irqbalance  absent
```

```zig
zig build -Doptimize=ReleaseFast
sudo goset -n 8 -cgroup -steer -fence --interval 1 -- ./zig-out/bin/_1brc B "" 8
```
