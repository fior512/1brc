# 1BRC
bare binary managed by the scheduler, 12 threads

### Perfomances (ms; 100M rows)
| lang | med | sd | min | max | 1B(12T) | link |
|---|---|---|---|---|---|---|
| **Zig** | 103.30 | 8.19 | 101.60 | 123.20 | 762 | [Zig](zig/README.md) |

> 100M: `synthetic_100M.txt` (9674 stations). 1B: `DB_1B.txt` (official, 413 stations).

### Ladder (ms; 1B rows; 12T; rank in column)
| lang | impl | official rank | official 1B | official 10k | synthetic |
|---|---|--:|--:|--:|--:|
| C | [austindonisan](https://github.com/austindonisan/1brc) | - | 334 (1) | 891 (1) | 612 (1) |
| C++ | [lehuyduc](https://github.com/lehuyduc/1brc-simd) | - | 672 (2) | 931 (2) | 834 (2) |
| Java | [artsiomkorzun](https://github.com/artsiomkorzun/1brc-walkthrough) | 2 | 697 (3) | 1168 (4) | 977 (4) |
| Java | jerrinot | 3 | 720 (4) | 1488 (7) | 1306 (8) |
| Java | [thomaswue](https://github.com/thomaswue/1brc-steps) | 1 | 738 (5) | 2102 (10) | 1445 (9) |
| **Zig** | **fior512** (me) | - | **761 (6)** | **1037 (3)** | **901 (3)** |
| Java | abeobk | 5 | 780 (7) | 2280 (11) | 1255 (6) |
| Java | royvanrijn | 7 | 847 (8) | 1545 (8) | 1258 (7) |
| Java | stephenvonworley | 6 | 867 (9) | 1278 (6) | 1167 (5) |
| Java | mtopolnik | 9 | 883 (10) | 1228 (5) | wrong |
| Java | serkan-ozal | 4 | 890 (11) | 3736 (13) | wrong |
| Java | merykittyunsafe | 10 | 1053 (12) | 3788 (14) | 1591 (10) |
| Java | gonix | 15 | 1202 (13) | 2002 (9) | 1855 (11) |
| Java | ebarlas | 20 | 1327 (14) | 2294 (12) | 1999 (12) |
| Java | jincongho | 25 | 1782 (15) | 10679 (15) | 3989 (13) |
| Java | gamlerhart | 30 | 2653 (16) | 12307 (16) | timeout |

> AMD Ryzen 5 7600X 6-Core Processor\
> official ladder: [Java leaderboard](https://github.com/gunnarmorling/1brc)\
> `wrong`: incorrect values on synthetic. `timeout`: killed at 180s on all 6 runs.

Official 1B:  413 stations (real name), 1B rows.\
Official 10k: 10k stations (rnd slice mix), 1B rows.\
Synthetic:   9674 stations (real name), 1B rows.

