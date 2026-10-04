# 1BRC

### Rules

- No `stdout` of produced stats
- Machine state: `watchcub bench --pinfreq=off --cstate=keep`
- Run: `sudo goset -n 1 -cgroup -steer -fence -interval 5`
- Iterations: **>10**

### Perfomances (ms)
| lang | med | sd | min | max |
|---|---|---|---|---|
| **Zig** | 78.97 | 0.582 | 78.45 | 80.55 |




### Outputs
**ZIG**
```zig
󰣇 training/zig/1brc ❯ sudo goset -n 1 -cgroup -steer -fence -interval 5 -- zig run src/main.zig
----------------- GOSET -----------------
Selection
  cpu  sel  steer  non-steer  core  sibl  isol  numa  nohz  rcu
    4   *       0        100   215    10           0
   10   !       1        115   215     4           0
    0   &       0        111   284     6           0
    6         342        173   284     0           0
    3           0        140   300     9           0
    9           0        160   300     3           0
    5           0        155   312    11           0
   11           0        157   312     5           0
    1           0        131   408     7           0
    7          14        277   408     1           0
    8           0        262   561     2           0
    2           0        299   561     8           0

Telemetry
  freq min  freq avg  freq max  irq steerable  irq non-steerable
   5.27GHz   5.44GHz   5.45GHz              0                 30

Run
  task           sched             steer
  poll   15@5ms  ctxsw vol      1  applied         40
  wall  78.45ms  ctxsw invol    0  rejected        26
  exit        0  migrations     0  remaining        0
                 run_delay    0ns  drift            0
                                   irqbalance  absent
```
