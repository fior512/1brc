# 1BRC
monitored with goset -n 8 -cgroup -steer -fence and scheduler managed MAX(12) threads

### Perfomances (ms; 100M rows)
| lang | med | sd | min | max | 1B(12T) | link |
|---|---|---|---|---|---|---|
| **Zig** | 139.25 | 4.37 | 136.50 | 149.80 | 1307 (930)| [Zig](zig/README.md) | 

### Ladder (ms; 1B rows; median of 3)
| lang | impl | official rank | official 1B 12T | official 10k 12T | synthetic 12T | official 1B 8T | official 10k 8T | synthetic 8T |
|---|---|---|---|---|---|---|---|---|
| C | [austindonisan](https://github.com/austindonisan/1brc) | - | 334 | 891 | 612 | 479 | 966 | 765 |
| C++ | [lehuyduc](https://github.com/lehuyduc/1brc-simd) | - | 672 | 931 | 834 | 894 | 1235 | 1126 |
| Java | artsiomkorzun | #2 | 697 | 1168 | 977 | 740 | 1355 | 1101 |
| Java | jerrinot | #3 | 720 | 1488 | 1306 | 818 | 1773 | 1568 |
| Java | thomaswue | #1 | 738 | 2102 | 1445 | 792 | 2261 | 1516 |
| Zig | **me** | - | **761** | **1037** | **901** | **960** | **1317** | **1155** |
| Java | abeobk | #5 | 780 | 2280 | 1255 | 926 | 2789 | 1421 |
| Java | royvanrijn | #7 | 847 | 1545 | 1258 | 1166 | 1920 | 1431 |
| Java | stephenvonworley | #6 | 867 | 1278 | 1167 | 1050 | 1516 | 1390 |
| Java | mtopolnik | #9 | 883 | 1228 | wrong (1187) | 1193 | 1649 | wrong (1551) |
| Java | serkan-ozal | #4 | 890 | 3736 | wrong (1461) | 1021 | 3686 | wrong (1542) |
| Java | merykittyunsafe | #10 | 1053 | 3788 | 1591 | 1168 | 4923 | 1761 |
| Java | gonix | #15 | 1202 | 2002 | 1855 | 1552 | 2398 | 2335 |
| Java | ebarlas | #20 | 1327 | 2294 | 1999 | 1772 | 2926 | 2545 |
| Java | jincongho | #25 | 1782 | 10679 | 3989 | 2149 | 10753 | 7055 |
| Java | gamlerhart | #30 | 2653 | 12307 | timeout | 4884 | 11759 | timeout |

> AMD Ryzen 5 7600X 6-Core Processor\
> official ladder: [Java leaderboard](https://github.com/gunnarmorling/1brc)\
> `wrong`: incorrect values on synthetic. `timeout`: killed at 180s on all 6 runs.

Official 1B:  413 stations (real name), 1B rows.\
Official 10k: 10k stations (rnd slice mix), 1B rows.\
Synthetic:   9674 stations (real name), 1B rows.

