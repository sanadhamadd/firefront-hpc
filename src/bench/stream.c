/*
 * STREAM triad: a[i] = b[i] + s * c[i], to measure the memory bandwidth of a node.
 * This is the number the roofline estimate needs (tools/roofline.py).
 *
 *   make stream
 *   OMP_NUM_THREADS=32 OMP_PROC_BIND=close OMP_PLACES=cores ./build/stream
 *
 * The three arrays together hold --doubles values (default 4e8, i.e. 3.2 GB),
 * far more than any cache, so the triad really runs from memory.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _OPENMP
#include <omp.h>
#endif

#include "../timers.h"

#ifndef GIT_COMMIT
#define GIT_COMMIT "unknown"
#endif

static void usage(const char *prog)
{
    printf("usage: %s [options]\n\n", prog);
    printf("  --doubles N    doubles in all three arrays together (default 4e8, i.e. 3.2 GB)\n");
    printf("  --reps N       number of timed triads, the best one counts (default 10)\n");
    printf("  --help\n");
}

/* same idea as in main.c: the compiler version contains spaces */
static void print_compiler(void)
{
#ifdef __VERSION__
    for (const char *c = __VERSION__; *c; c++)
        putchar(*c == ' ' ? '_' : *c);
#else
    printf("unknown");
#endif
}

/* same as in main.c: OMP_PLACES of the run, "none" if not set */
static void print_places(void)
{
    const char *v = NULL;
#ifdef _OPENMP
    v = getenv("OMP_PLACES");
#endif
    if (!v || !*v) {
        printf("none");
        return;
    }
    for (const char *c = v; *c; c++)
        putchar(*c == ' ' ? '_' : *c);
}

int main(int argc, char **argv)
{
    double total = 4e8;
    int reps = 10;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(argv[0]);
            return 1;
        }
        if (i + 1 >= argc) {
            fprintf(stderr, "missing value for %s\n", argv[i]);
            return 1;
        }
        const char *v = argv[++i];
        if (strcmp(argv[i - 1], "--doubles") == 0)   total = atof(v);   /* atof so 4e8 works */
        else if (strcmp(argv[i - 1], "--reps") == 0) reps = atoi(v);
        else {
            fprintf(stderr, "unknown option %s\n", argv[i - 1]);
            usage(argv[0]);
            return 1;
        }
    }
    if (total < 3e3 || reps < 1) {
        fprintf(stderr, "--doubles must be at least 3000 and --reps at least 1\n");
        return 1;
    }

    long long n = (long long)(total / 3.0);     /* doubles per array */
    double *a = malloc((size_t)n * sizeof(double));
    double *b = malloc((size_t)n * sizeof(double));
    double *c = malloc((size_t)n * sizeof(double));
    if (!a || !b || !c) {
        fprintf(stderr, "could not allocate 3 x %lld doubles\n", n);
        return 1;
    }

    int threads = 1;
#ifdef _OPENMP
    threads = omp_get_max_threads();
#endif

    /* first touch: each thread writes the part it will use in the triad, with the
       same static schedule, so the memory pages land on that thread's socket */
#ifdef _OPENMP
#pragma omp parallel for schedule(static)
#endif
    for (long long i = 0; i < n; i++) {
        a[i] = 0.0;
        b[i] = 2.0;
        c[i] = 0.5;
    }

    const double s = 3.0;
    double best = 1e30;
    for (int r = 0; r < reps; r++) {
        double t0 = wall_seconds();
#ifdef _OPENMP
#pragma omp parallel for schedule(static)
#endif
        for (long long i = 0; i < n; i++)
            a[i] = b[i] + s * c[i];
        double t = wall_seconds() - t0;
        if (t < best) best = t;
    }

    /* every a[i] must be 2 + 3 * 0.5; this also stops the compiler from dropping the loop */
    long long wrong = 0;
    for (long long i = 0; i < n; i++)
        if (a[i] != 3.5) wrong++;
    if (wrong) {
        fprintf(stderr, "triad gave %lld wrong values\n", wrong);
        return 1;
    }

    /* STREAM counts 3 arrays x 8 bytes per element (2 reads + 1 write); the extra
       write-allocate read of a[] that most CPUs do is not counted, as in the original */
    double bytes = 3.0 * 8.0 * (double)n;
    double bw_gbs = bytes / best / 1e9;

    printf("stream triad: 3 x %lld doubles (%.2f GB), %d thread(s), best of %d\n",
           n, bytes / 1e9, threads, reps);
    printf("RESULT variant=stream n=%lld reps=%d ranks=1 threads=%d t_best=%.6f bw_gbs=%.2f commit=%s compiler=",
           n, reps, threads, best, bw_gbs, GIT_COMMIT);
    print_compiler();
    printf(" places=");
    print_places();
    printf("\n");

    free(a);
    free(b);
    free(c);
    return 0;
}
