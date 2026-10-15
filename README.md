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
| **Zig** | 391.74 | 9.14 | 387.31 | 419.07 | 3.72s | [Zig](zig/README.md) |


### Outputs
**ZIG**

```zig
----------------- GOSET -----------------
Selection
  cpu  sel  steer  non-steer  core  sibl  isol  numa  nohz  rcu
    4   *       0        165   333    10           0
   10   *       0        168   333     4           0
    0   *       0        206   451     6           0
    6   *       0        245   451     0           0
    2   *       0        257   523     8           0
    8   *       0        266   523     2           0
    9   *     308        249   533     3           0
    3   *       1        284   533     9           0
    7   &       0        256   543     1           0
    1           1        287   543     7           0
   11           0        252   581     5           0
    5           0        329   581    11           0

Telemetry
  cpu  freq min  freq avg  freq max  throttle count  irq steerable  irq non-steerable
  0     4.67GHz   4.67GHz   4.68GHz               0              0              1.50k
  2     4.67GHz   4.67GHz   4.68GHz               0              0              1.28k
  3     4.67GHz   4.67GHz   4.68GHz               0              0              1.35k
  4     4.67GHz   4.67GHz   4.68GHz               0              0              1.22k
  6     4.67GHz   4.67GHz   4.68GHz               0              0              1.33k
  8     4.67GHz   4.67GHz   4.68GHz               0              0              1.21k
  9     4.67GHz   4.67GHz   4.68GHz               0              0              1.26k
  10    4.67GHz   4.67GHz   4.68GHz               0              0              1.17k
  all   4.67GHz   4.67GHz   4.68GHz               0              0              10.3k

Run
  task            sched                steer
  poll  3544@1ms  ctxsw vol        24  applied         40
  wall     3.72s  ctxsw invol     567  rejected        26
  exit         0  migrations        4  remaining        1
                  run_delay    1.33ms  drift            0
                                       irqbalance  absent
```

```zig
zig build -Doptimize=ReleaseFast
sudo goset -n 1 -cgroup -steer -fence --interval 1 -- ./zig-out/bin/_1brc B
```
