# 1BRC

### Rules

- No `stdout` of produced stats
- Machine state: `watchcub bench --pinfreq=off --cstate=keep`
- Run: `sudo goset -n 1 -cgroup -steer -fence -interval 5`
- Iterations: **>10**

### Perfomances (ms; 100M rows)
| lang | med | sd | min | max | 1B | link |
|---|---|---|---|---|---|---|
| **Zig** | 2895.00 | 31.00 | 2830.00 | 2920.00 | 28.33s | [Zig](zig/README.md) |


### Outputs
**ZIG**

```zig
----------------- GOSET -----------------
Selection
  cpu  sel  steer  non-steer  core  sibl  isol  numa  nohz  rcu
   11   *       0         37   419     5           0
    5   !      94        382   419    11           0
    7   &       0        241   586     1           0
    1           0        345   586     7           0
    6           0        247   600     0           0
    0           0        353   600     6           0
    2          11        275   605     8           0
    8         314        330   605     2           0
    4           0        295   718    10           0
   10           0        423   718     4           0
    9           0        332   760     3           0
    3           0        428   760     9           0

Telemetry
  freq min  freq avg  freq max  irq steerable  irq non-steerable
   5.08GHz   5.27GHz   5.45GHz              0              11.2k

Run
  task            sched                steer
  Poll  5665@5ms  ctxsw vol         1  applied         40
  wall    28.33s  ctxsw invol     768  rejected        26
  exit         0  migrations        1  remaining        0
                  run_delay    2.93ms  drift            0
                                       irqbalance  absent
```
> zig build -Doptimize=ReleaseFast && sudo goset -n 1 -cgroup -steer -fence --interval 5 -- ./zig-out/bin/_1brc B
