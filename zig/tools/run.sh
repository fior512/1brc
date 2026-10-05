cd "$(dirname "$0")/.." || exit 1
zig build -Doptimize=ReleaseFast && sudo -v && for i in $(seq 10); do
    sudo goset -n 1 -cgroup -steer -fence --interval 5 -- ./zig-out/bin/_1brc M
    sleep 5
done 2>&1 | tee out.txt

awk '
/^[ \t]*wall[ \t]/ {
    v = $2 + 0
    if      ($2 ~ /ms$/)        ;
    else if ($2 ~ /(us|µs)$/)   v /= 1000
    else if ($2 ~ /ns$/)        v /= 1000000
    else                        v *= 1000
    w[++n] = v; sum += v
}
END {
    if (!n) { print "no wall lines found"; exit 1 }
    for (i = 2; i <= n; i++) { x = w[i]; for (j = i - 1; j >= 1 && w[j] > x; j--) w[j+1] = w[j]; w[j+1] = x }
    med = (n % 2) ? w[(n+1)/2] : (w[n/2] + w[n/2+1]) / 2
    m = sum / n
    for (i = 1; i <= n; i++) ss += (w[i] - m) ^ 2
    sd = (n > 1) ? sqrt(ss / (n - 1)) : 0
    printf "%-7s%10.2f\n%-7s%10.2f\n%-7s%10.2f\n%-7s%10.2f\n", \
        "med", med, "sd", sd, "min", w[1], "max", w[n]
}' out.txt
