// usage: gen <rows> <out> ; station names come from data/cities.txt (first 10000 unique)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
static uint64_t s = 88172645463325252ULL;
static inline uint64_t rnd(void){ s ^= s<<13; s ^= s>>7; s ^= s<<17; return s; }
int main(int argc, char **argv){
    long n = atol(argv[1]);
    FILE *in = fopen("data/cities.txt","r");
    static char *names[10000]; int k = 0; char line[512];
    while (k < 10000 && fgets(line,sizeof line,in)){
        if (line[0]=='#') continue;
        char *sc = strchr(line,';'); if(!sc) continue;
        *sc = 0; names[k++] = strdup(line);
    }
    FILE *out = fopen(argv[2],"w");
    static char buf[1<<20]; setvbuf(out, buf, _IOFBF, sizeof buf);
    for (long i=0;i<n;i++){
        int t = (int)(rnd()%1999) - 999;
        const char *sign = t<0 ? "-" : ""; if (t<0) t=-t;
        fprintf(out,"%s;%s%d.%d\n", names[rnd()%k], sign, t/10, t%10);
    }
    fclose(out); return 0;
}
