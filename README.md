# 1BRC

### Rules

- No `stdout` of produced stats
- Machine state: `watchcub bench --pinfreq=off --cstate=keep`
- Run: `sudo goset -n 1 -cgroup -steer -fence -interval 5`
- Iterations: **>10**

### Perfomances (ms; 100M rows)
| lang | med | sd | min | max | 1B | link |
|---|---|---|---|---|---|---|
| **Zig** | 1530.00 | 12.65 | 1500.00 | 1540.00 | 14.89s | [Zig](zig/README.md) |


### Outputs
**ZIG**

```zig
----------------- GOSET -----------------
Selection
  cpu  sel  steer  non-steer  core  sibl  isol  numa  nohz  rcu
   10   *       0         52   184     4           0
    4   !       0        132   184    10           0
    9   &       0         40   186     3           0
    3           0        146   186     9           0
    5           0         89   193    11           0
   11           0        104   193     5           0
    2           0         53   313     8           0
    8           0        260   313     2           0
    6           0        135   489     0           0
    0         218        354   489     6           0
    7           0         73   525     1           0
    1           0        452   525     7           0

Telemetry
  freq min  freq avg  freq max  throttle count  irq steerable  irq non-steerable
   4.35GHz   5.30GHz   5.43GHz               0              0              5.66k

Run
  task             sched                  steer
  poll  14820@1ms  ctxsw vol           1  applied         40
  wall     14.89s  ctxsw invol        32  rejected        26
  exit          0  migrations          1  remaining        0
                   run_delay    149.27us  drift            0
                                          irqbalance  absent
```

```zig
zig build -Doptimize=ReleaseFast
sudo goset -n 1 -cgroup -steer -fence --interval 1 -- ./zig-out/bin/_1brc B
```
