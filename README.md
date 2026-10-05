# 1BRC

### Rules

- No `stdout` of produced stats
- Machine state: `watchcub bench --pinfreq=off --cstate=keep`
- Run: `sudo goset -n 1 -cgroup -steer -fence -interval 5`
- Iterations: **>10**

### Perfomances (ms; 100M rows)
| lang | med | sd | min | max | 1B |
|---|---|---|---|---|---|
| **Zig** | 4580 | 35.98 | 4550 | 4660 | 45.75s |


### Outputs
**ZIG**

```zig
----------------- GOSET -----------------
Selection
  cpu  sel  steer  non-steer  core  sibl  isol  numa  nohz  rcu
    9   *       0         45   256     3           0
    3   !       0        211   256     9           0
    1   &       0          7   428     7           0
    7           0        421   428     1           0
    2          94        141   457     8           0
    8           6        316   457     2           0
    4           0         93   542    10           0
   10           0        449   542     4           0
    6           7        266   576     0           0
    0           0        310   576     6           0
   11           0        338   692     5           0
    5         360        354   692    11           0

Telemetry
  freq min  freq avg  freq max  irq steerable  irq non-steerable
   4.69GHz   5.29GHz   5.40GHz              0              1.52k

Run
  task           sched                 steer
  poll  914@5ms  ctxsw vol          1  applied         40
  wall    4.57s  ctxsw invol       15  rejected        26
  exit        0  migrations         1  remaining        1
                 run_delay    63.52us  drift            0
                                       irqbalance  absent

  not reported: throttle
```
> zig build -Doptimize=ReleaseFast && sudo goset -n 1 -cgroup -steer -fence --interval 5 -- ./zig-out/bin/_1brc
