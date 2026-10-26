#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _OPENMP
#include <omp.h>
#endif
#ifdef USE_MPI
#include <mpi.h>
#endif

#include "params.h"
#include "sim.h"
#include "timers.h"

#ifndef VARIANT
#define VARIANT "serial"
#endif
#ifndef GIT_COMMIT
#define GIT_COMMIT "unknown"
#endif

/* the compiler version contains spaces, which would break the RESULT line */
static void print_compiler(void)
{
#ifdef __VERSION__
    for (const char *c = __VERSION__; *c; c++)
        putchar(*c == ' ' ? '_' : *c);
#else
    printf("unknown");
#endif
}

/* OMP_PLACES of the run (cores = one thread per physical core, threads = per hardware
   thread), "none" if it is not set or the build has no OpenMP; no spaces in the RESULT line */
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

/* MPI_Finalize when built with MPI; returns code so it can end main */
static int finish(int code)
{
#ifdef USE_MPI
    MPI_Finalize();
#endif
    return code;
}

int main(int argc, char **argv)
{
    int rank = 0, ranks = 1;
#ifdef USE_MPI
    /* only the main thread of each rank calls MPI, outside the OpenMP loops */
    int provided;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &ranks);
#endif

    Params p;
    params_defaults(&p);
    if (params_parse(&p, argc, argv))
        return finish(1);

    int threads = 1;
#ifdef _OPENMP
    threads = omp_get_max_threads();
#endif

    if (rank == 0)
        printf("firefront %s: %d x %d cells, %d steps, seed %llu, wind %.1f m/s towards %.0f deg, humidity %.2f, %d rank(s), %d thread(s)\n",
               VARIANT, p.nx, p.ny, p.steps, (unsigned long long)p.seed,
               p.wind_speed, p.wind_dir_deg, p.humidity, ranks, threads);

    Sim *sim = sim_create(&p);
    int failed = (sim == NULL);
#ifdef USE_MPI
    int any_failed;
    MPI_Allreduce(&failed, &any_failed, 1, MPI_INT, MPI_MAX, MPI_COMM_WORLD);
    failed = any_failed;
#endif
    if (failed) {
        if (rank == 0)
            fprintf(stderr, "could not set up the simulation\n");
        sim_free(sim);
        return finish(1);
    }

    /* the first steps are not timed (page faults, caches) */
    int warmup = (p.steps > 20) ? 10 : 0;
    double t_start = 0.0;

    for (int step = 1; step <= p.steps; step++) {
        if (step == warmup + 1)
            t_start = wall_seconds();
        sim_step(sim);
        if (p.report_every > 0 && step % p.report_every == 0) {
            long long burning = sim_count_burning(sim);      /* every rank takes part */
            long long burnt = sim_count_burnt(sim);
            if (rank == 0)
                printf("step %d: %lld burning, %lld burnt\n", step, burning, burnt);
        }
    }
    double t_total = (p.steps > 0) ? wall_seconds() - t_start : 0.0;

    long long timed_steps = p.steps - warmup;
    double cells_per_s = (t_total > 0.0)
        ? (double)p.nx * (double)p.ny * (double)timed_steps / t_total : 0.0;

    /* these sum over all ranks, so every rank calls them */
    long long burning = sim_count_burning(sim);
    long long burnt = sim_count_burnt(sim);
    unsigned long long checksum = (unsigned long long)sim_checksum(sim);

    if (rank == 0) {
        printf("RESULT variant=%s nx=%d ny=%d steps=%d seed=%llu ranks=%d threads=%d "
               "t_total=%.4f cells_per_s=%.3e burning=%lld burnt=%lld checksum=0x%016llx commit=%s compiler=",
               VARIANT, p.nx, p.ny, p.steps, (unsigned long long)p.seed, ranks, threads,
               t_total, cells_per_s, burning, burnt, checksum, GIT_COMMIT);
        print_compiler();
        printf(" ignitions=%d places=", p.ignitions);
        print_places();
        printf(" humidity=%g\n", p.humidity);
    }

    if (p.snapshot && sim_write_pgm(sim, p.snapshot) != 0 && rank == 0)
        fprintf(stderr, "could not write %s (with more than one rank the snapshot is not supported yet)\n", p.snapshot);

    sim_free(sim);
    return finish(0);
}
