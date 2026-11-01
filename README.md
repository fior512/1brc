# 1BRC

### Rules

- No `stdout` of produced stats
- Run: `sudo goset -n 1 -cgroup -steer -fence -interval 5`
- Iterations: **>10**
- Multithreading: 8 threads

### Perfomances (ms; 100M rows)
| lang | med | sd | min | max | 1B(real) | link |
|---|---|---|---|---|---|---|
| **Zig** | 150.47 | 0.50 | 149.94 | 151.72| 1.472s (1.026s)| [Zig](zig/README.md) | 


### Outputs
**ZIG**

```zig
----------------- GOSET -----------------
Selection
  cpu  sel  steer  non-steer  core  sibl  isol  numa  nohz  rcu
    7   *       0          4    80     1           0
    1   *       0         76    80     7           0
    9   *       0         26   170     3           0
    3   *      10        144   170     9           0
    6   *       0         25   257     0           0
    0   *       0        232   257     6           0
   10   *       0         71   264     4           0
    4   *       0        193   264    10           0
    5   &      12        178   449    11           0
   11         291        271   449     5           0
    8           0         32   928     2           0
    2           0        896   928     8           0

Telemetry
  cpu  freq min  freq avg  freq max  throttle count  irq steerable  irq non-steerable
  0     3.10GHz   5.04GHz   5.21GHz               0              0                625
  1     2.99GHz   5.04GHz   5.21GHz               0              0                601
  3     3.10GHz   5.04GHz   5.21GHz               0              0                676
  4     2.99GHz   5.08GHz   5.45GHz               0              0                622
  6     3.10GHz   5.04GHz   5.21GHz               0              0                602
  7     2.99GHz   5.06GHz   5.21GHz               0              0                564
  9     3.10GHz   5.04GHz   5.21GHz               0              0                539
  10    2.99GHz   5.08GHz   5.45GHz               0              0                590
  all   2.99GHz   5.05GHz   5.45GHz               0              0              4.82k

Run
  task            sched                   steer
  poll  1458@1ms  ctxsw vol           12  applied         40
  wall    1.472s  ctxsw invol        180  rejected        26
  util      778%  migrations           3  remaining        1
  exit         0  run_delay     10.230μs  drift            0
                                          irqbalance  absent
```

```zig
zig build -Doptimize=ReleaseFast
sudo goset -n 8 -cgroup -steer -fence --interval 1 -- ./zig-out/bin/_1brc B "" 8
```
