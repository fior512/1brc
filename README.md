# 1BRC

### Rules

- No `stdout` of produced stats
- Machine state: `watchcub bench --pinfreq=off --cstate=keep`
- Run: `sudo goset -n 1 -cgroup -steer -fence -interval 5`
- Iterations: **>10**

### Perfomances (ms; 100M rows)
| lang | med | sd | min | max | 1B | link |
|---|---|---|---|---|---|---|
| **Zig** | 3995.00 | 48.41 | 3940.00 | 4060.00 | 40.90s | [Zig](zig/README.md) |


### Outputs
**ZIG**

```zig
----------------- GOSET -----------------
Selection
  cpu  sel  steer  non-steer   core  sibl  isol  numa  nohz  rcu
    6   *      93        256    887     0           0
    0   !       0        631    887     6           0
    5   &      11        420    971    11           0
   11           0        551    971     5           0
    2          20        351    978     8           0
    8         247        627    978     2           0
    3           0        488  1.04k     9           0
    9           0        557  1.04k     3           0
    7           0        480  1.09k     1           0
    1           0        606  1.09k     7           0
   10           0        477  1.10k     4           0
    4           7        622  1.10k    10           0

Telemetry
  freq min  freq avg  freq max  irq steerable  irq non-steerable
   4.98GHz   5.14GHz   5.35GHz              0              18.0k

Run
  task            sched                steer
  Poll  8179@5ms  ctxsw vol         1  applied         40
  wall    40.90s  ctxsw invol     230  rejected        26
  exit         0  migrations        1  remaining        0
                  run_delay    1.63ms  drift            0
                                       irqbalance  absent
```
> zig build -Doptimize=ReleaseFast && sudo goset -n 1 -cgroup -steer -fence --interval 5 -- ./zig-out/bin/_1brc B
