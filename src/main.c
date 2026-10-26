#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

#ifdef _OPENMP
#include <omp.h>
#endif
#ifdef USE_MPI
#include <mpi.h>
#endif

#include "decomp.h"
#include "params.h"
#include "sim.h"
#include "timers.h"

/* the burnt area is combined over the ranks every this many steps (and at the end) */
#define REDUCE_EVERY 50

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

/* Every rank reads the same options, so only rank 0 needs to print usage or errors.
   The other ranks send stdout and stderr to /dev/null while the options are read. */
static int quiet_fd[2] = { -1, -1 };

static int open_null(void)
{
    return open("/dev/null", O_WRONLY);
}

static void quiet_begin(int rank)
{
    if (rank == 0) return;
    fflush(stdout);
    fflush(stderr);
    int null_fd = open_null();
    if (null_fd < 0) return;
    quiet_fd[0] = dup(STDOUT_FILENO);
    quiet_fd[1] = dup(STDERR_FILENO);
    dup2(null_fd, STDOUT_FILENO);
    dup2(null_fd, STDERR_FILENO);
    close(null_fd);
}

static void quiet_end(void)
{
    if (quiet_fd[0] < 0) return;
    fflush(stdout);
    fflush(stderr);
    dup2(quiet_fd[0], STDOUT_FILENO);
    dup2(quiet_fd[1], STDERR_FILENO);
    close(quiet_fd[0]);
    close(quiet_fd[1]);
    quiet_fd[0] = quiet_fd[1] = -1;
}

/* largest and sum of a value over all ranks (just the value without MPI) */
static void max_and_sum(double v, double *max, double *sum)
{
#ifdef USE_MPI
    MPI_Allreduce(&v, max, 1, MPI_DOUBLE, MPI_MAX, MPI_COMM_WORLD);
    MPI_Allreduce(&v, sum, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
#else
    *max = v;
    *sum = v;
#endif
}

/* number of compute nodes the ranks run on */
static int count_nodes(void)
{
#ifdef USE_MPI
    MPI_Comm node;
    int node_rank, first, nodes;
    MPI_Comm_split_type(MPI_COMM_WORLD, MPI_COMM_TYPE_SHARED, 0, MPI_INFO_NULL, &node);
    MPI_Comm_rank(node, &node_rank);
    first = (node_rank == 0);
    MPI_Allreduce(&first, &nodes, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
    MPI_Comm_free(&node);
    return nodes;
#else
    return 1;
#endif
}

static void barrier(void)
{
#ifdef USE_MPI
    MPI_Barrier(MPI_COMM_WORLD);
#endif
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
    quiet_begin(rank);
    int bad_options = params_parse(&p, argc, argv);
    quiet_end();
    if (bad_options)
        return finish(1);

    int threads = 1;
#ifdef _OPENMP
    threads = omp_get_max_threads();
#endif
    int nodes = count_nodes();

    if (rank == 0)
        printf("firefront %s: %d x %d cells, %d steps, seed %llu, wind %.1f m/s towards %.0f deg, humidity %.2f, "
               "%d rank(s) on %d node(s), %d thread(s), %s\n",
               VARIANT, p.nx, p.ny, p.steps, (unsigned long long)p.seed,
               p.wind_speed, p.wind_dir_deg, p.humidity, ranks, nodes, threads, decomp_name(p.decomp));

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

    int px, py;
    sim_rank_grid(sim, &px, &py);

    /* The first steps are not timed (page faults, caches). All ranks start the clock
       together after a barrier; the run time is that of the slowest rank. */
    int warmup = (p.steps > 20) ? 10 : 0;
    double t_start = 0.0, t_reduce = 0.0;
    if (warmup == 0) {
        barrier();
        t_start = wall_seconds();
    }

    for (int step = 1; step <= p.steps; step++) {
        sim_step(sim);

        /* burnt area over all ranks every REDUCE_EVERY steps, not every step: each
           Allreduce makes all ranks wait for each other */
        int reduce = (step % REDUCE_EVERY == 0);
        int report = (p.report_every > 0 && step % p.report_every == 0);
        if (reduce || report) {
            double t0 = wall_seconds();
            long long burning = sim_count_burning(sim);      /* every rank takes part */
            long long burnt = sim_count_burnt(sim);
            if (step > warmup)
                t_reduce += wall_seconds() - t0;
            if (report && rank == 0)
                printf("step %d: %lld burning, %lld burnt\n", step, burning, burnt);
        }

        if (step == warmup && warmup > 0) {
            barrier();
            sim_reset_times(sim);
            t_start = wall_seconds();
        }
    }
    double t_mine = (p.steps > 0) ? wall_seconds() - t_start : 0.0;

    double t_halo_mine, t_compute_mine;
    sim_times(sim, &t_halo_mine, &t_compute_mine);
    double t_total, t_sum, t_halo, t_halo_sum, t_compute, t_compute_sum, t_reduce_max, t_reduce_sum;
    max_and_sum(t_mine, &t_total, &t_sum);
    max_and_sum(t_halo_mine, &t_halo, &t_halo_sum);
    max_and_sum(t_compute_mine, &t_compute, &t_compute_sum);
    max_and_sum(t_reduce, &t_reduce_max, &t_reduce_sum);
    /* how much longer the slowest rank computes than the average one (1 = even) */
    double imbalance = (t_compute_sum > 0.0) ? t_compute / (t_compute_sum / ranks) : 1.0;

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
        printf(" humidity=%g", p.humidity);
        /* fields added for MPI; only appended, so older logs and the parser still work.
           t_halo, t_compute and t_reduce are the largest value over the ranks. */
        printf(" nodes=%d decomp=%s px=%d py=%d overlap=%d t_halo=%.4f t_compute=%.4f t_reduce=%.4f imbalance=%.3f\n",
               nodes, decomp_name(p.decomp), px, py, p.overlap, t_halo, t_compute, t_reduce_max, imbalance);
    }

    if (p.snapshot) {
        int bad = sim_write_pgm(sim, p.snapshot);   /* every rank takes part */
        if (bad && rank == 0)
            fprintf(stderr, "could not write %s\n", p.snapshot);
    }

    sim_free(sim);
    return finish(0);
}
