# Reproducing the results

This file lists the commands that reproduce every main result in the report, at two levels:

- **Level A, no cluster needed (minutes):** rebuild every table and figure from the job logs committed in `results/raw/`. See [section 6](#6-rebuild-tables-and-figures-from-the-committed-logs).
- **Level B, on the SciTech cluster:** build, check correctness, and rerun the timed experiments through Slurm. See sections 2–5.

The **main result** to reproduce is the strong-scaling series on the 8192 × 8192 grid (400 steps, `--ignitions 16`, seed 42). Every run of it, serial or parallel, must print the checksum **`0xb8683c550fa95bd6`**.

## 0. Quick check (any machine, about 1 minute)

    git clone https://github.com/sanadhamadd/firefront-hpc.git && cd firefront-hpc
    make test                                   # model checks; ends with "all checks passed"
    make && ./build/firefront_serial --steps 100 | grep -o 'checksum=0x[0-9a-f]*'
    # expected: checksum=0x74cfadfb78e73134     (default 1024 x 1024 grid, 100 steps)

`make test` prints `skipped` for the OpenMP part if the compiler has no OpenMP. On a Mac, `gcc` is Apple clang, so pass Homebrew GCC: `OMP_CC=gcc-16 make test`.

## 1. Code versions

Every `RESULT` line records the commit the binary was built from (`commit=`), so each figure can be traced to its code. Later commits did not change the simulation: all versions give the same checksum.

| Experiment | Built from | Tag / note |
|---|---|---|
| E1, E2, first STREAM | `610e539` | |
| Grid-size sweep (E6), STREAM rerun | `7c686c8` | tag `v0.2-cluster` = `82d88cf` (same code) |
| E5 (MPI decomposition, MPI part of E2) | `76eff8c` (submitted from `674dab1`) | |
| E3, E4 (hybrid, weak scaling) | `ce2e211` | tag `v0.3-mpi` |
| E7 (overlap), E9 (timers) | `4bf2cd1` | branch `khadija/e7-overlap-profiling`, merged in `0edabc4` |
| E8 (kernel optimisation: tile skipping) | `dd8ea11` | merge of PR #5; build job 35387 |
| E10 (GPU) | to be added | phase 3c |

To rerun one experiment exactly, check out its commit (`git checkout ce2e211`) before building. To rerun everything with the current code, build `main`; the checksums must not change.

## 2. Environment

**Cluster:** SciTech, nodes `haskell` (2 × AMD EPYC 9755) and `julia` (2 × AMD EPYC 9745), Slurm partition `cpu`, account `hpcclass`, QOS `student` (both defaults). Details and limits: [env/cluster.md](env/cluster.md).

**Modules** (from [env/modules.txt](env/modules.txt); the job scripts load them):

| Purpose | Module |
|---|---|
| C compiler, OpenMP | `GCC/13.2.0` |
| MPI | `OpenMPI/4.1.6-GCC-13.2.0` (loads GCC/13.2.0). Do **not** use the node's system `mpirun` (Open MPI 5.0.7). |
| GPU (E10) | `hpc-course-cuda/12.8.1`, `nvhpc/25.7` |
| Counters (optional) | `PAPI/7.1.0-GCCcore-13.2.0` (no LIKWID module exists) |

**Compiler flags** (from the [Makefile](Makefile)): `-O3 -march=native -std=c11 -Wall -Wextra -ffp-contract=off`, plus `-fopenmp` for the OpenMP, MPI and STREAM builds. On haskell, GCC 13.2 resolves `-march=native` to `znver4`. `-ffp-contract=off` keeps serial, OpenMP and MPI results identical bit for bit.

**MPI transport.** Open MPI's default UCX layer crashed at start-up in some 2-node runs (see [docs/handover.md](docs/handover.md)). All E5, E3, E4 and E7 jobs therefore set

    OMPI_MCA_pml=ob1  OMPI_MCA_btl=self,vader,tcp  OMPI_MCA_btl_vader_backing_directory=/tmp

on one node too, so all timings use the same MPI path. Each log prints this as `MPI settings:` or `transport=`. `MPI_DEFAULTS=1` turns it off. Exception: E3 job 34260 ran with the default transport (see [docs/alejandro_e3_e4_reproduction.md](docs/alejandro_e3_e4_reproduction.md)).

**Python** (for parsing and plots): `pip install -r env/requirements.txt` (numpy, matplotlib, pandas). Checked with Python 3.14, numpy 2.5, matplotlib 3.11, pandas 3.1.

## 3. Build and correctness gate (cluster)

Never build or run on the login node (`rust`): it is a small VM without AVX, so `-march=native` there targets the wrong CPU. Build in a job on a compute node:

    sbatch slurm/build.sbatch

It runs `make clean`, `make`, `make omp`, `make stream`, `OMP_CC=gcc make test`, `make mpi` and `make test-mpi` (1–8 ranks, both decompositions, both overlap modes), and logs which `mpicc`/`mpirun` it used. Check `results/raw/build_<jobid>.out`:

- it ends with `all checks passed` and `all MPI checks passed`;
- the OpenMP lines say `ok`, not `skipped`;
- `mpicc` and `mpirun` point into the OpenMPI/4.1.6 module.

**Checksum gate.** Every timed MPI job compares its result with the serial reference and prints `checksum ok`; E7 also runs both modes with `--verify-only` before timing them and stops if either one differs. A run that does not reproduce `0xb8683c550fa95bd6` (8192², 400 steps) is not used.

**One-time launcher check**, after the build (one node, then two):

    sbatch slurm/mpi_check.sbatch
    sbatch --nodes=2 --ntasks-per-node=2 --nodelist=haskell,julia slurm/mpi_check.sbatch

The end of `results/raw/mpi_check_<jobid>.out` lists each launcher as `works` or `fails`. On 17 Nov 2026, `srun --cpu-bind=cores` (the default `LAUNCH`), `srun --mpi=pmix` and `mpirun` worked; `srun --mpi=pmi2` did not.

## 4. Rules all timed jobs follow

- **Workload:** 8192 × 8192 cells, 400 steps, `--ignitions 16`, seed 42, all other model options at their defaults (unless the experiment changes them). The first 10 steps are an untimed warm-up; 390 steps are timed.
- **One repetition per job** (`REP=1,2,3`), at most 10 minutes. 3 repetitions per configuration (E7: 5 paired repetitions). We report the median with min–max.
- **Queue limits** of the student QOS: 64 CPUs = **32 physical cores** per user at a time, 4 running and 8 queued jobs. Two-node runs use at most 2 × 16 cores.
- **One timed job at a time:** build and timed jobs share the job name `firefront` with `--dependency=singleton`.
- **Pinning:** OpenMP: `OMP_PROC_BIND=close`, `OMP_PLACES=cores`, one socket (`--sockets-per-node=1`). MPI: `srun --cpu-bind=cores --hint=nomultithread`.
- **Node:** one-node runs are pinned to `haskell` (`--nodelist=haskell`), two-node runs use `haskell,julia`.
- **Shared nodes:** the partition sets `OverSubscribe=FORCE:2`, so other users' jobs may share our cores; `--exclusive` does not prevent it. Every log records the node load and the jobs on it (anonymised) at start and end.

## 5. Experiments

Submit everything from the repository root after a successful build (section 3). Logs are written to `results/raw/`.

### E1 – Serial baseline, and E2 – OpenMP strong scaling

    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e1_baseline.sbatch;    done   # serial, 1 core
    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e2_omp_threads.sbatch; done   # 1,2,4,8,16,32 threads + 64 hyper-threads

Logs: `e1_baseline_<id>.out` (jobs 24880–24882), `e2_omp_threads_<id>.out` (24883–24885). Expected: serial median 81.95 s; 32 threads 3.24 s (25.3×, efficiency 0.79).

### STREAM triad (memory bandwidth, roofline bound)

    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/stream.sbatch; done
    python tools/roofline.py 68          # prints the bound for 68 GB/s at 6, 7 and 10 bytes per update

Expected: about 67–68 GB/s on 32 cores, about 28 GB/s per 8-core chiplet. The bandwidth reached at a given thread count depends on which cores Slurm gives the job (see [docs/handover.md](docs/handover.md)).

### E6 – Resolution / grid-size sweep (OpenMP, 32 threads)

    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/size_sweep.sbatch; done

Each job runs 2048², 4096², 8192² and 16384², with the default humidity and with `--humidity 1` (no fire spread). Expected: about 8,000 million cell updates per second at every size (compute-bound).

### E5 – MPI decomposition (strips vs blocks) and the MPI part of E2

    DRY_RUN=1 bash slurm/submit_e5.sh                      # prints the 51 sbatch commands
    LAUNCH="srun --cpu-bind=cores" bash slurm/submit_e5.sh  # submits them, waits while 8 jobs are queued

Strips and blocks with 1, 2, 4, 8, 16 and 32 ranks on haskell and 8, 16 and 32 ranks over haskell and julia, one rank per core, 3 repetitions. Leave it running (e.g. in `tmux`). Every log must say `checksum ok`. The single-node julia control (job 33981) is in `results/raw/e5_checks/`, the UCX crash tests in `results/raw/e5_ucx_tests/`.

### E3 – Hybrid MPI + OpenMP split, and E4 – Weak scaling

Both use `slurm/hybrid.sbatch` through the planner `tools/submit_phase3a.py`, which prints the commands by default and skips configurations that already have checked logs:

    bash slurm/submit_phase3a.sh e3        # 32 cores as 8x4, 16x2, 32x1 ranks x threads, on 1 node and on 2 nodes
    bash slurm/submit_phase3a.sh e4        # 1024^2 cells per core: 1, 4, 16, 32 cores
    bash slurm/submit_phase3a.sh e3 --submit --probe-1 results/raw/mpi_check_<1-node id>.out --probe-2 results/raw/mpi_check_<2-node id>.out

E4 grids: 1024² on 1 core (1 × 1), 2048² on 4 (1 × 4), 4096² on 16 (4 × 4), 8192 × 4096 on 32 (2 nodes, 8 × 4). Logs: `hybrid_<id>.out` (jobs 34260–34382). Full notes: [docs/alejandro_e3_e4_reproduction.md](docs/alejandro_e3_e4_reproduction.md).

### E7 – Optimisation: blocking vs overlapped halo exchange

First an untimed two-node correctness check of both modes, then the paired sweep (4, 8, 16, 32 ranks on haskell; 8, 16, 32 ranks on two nodes; blocks; 5 pairs each, blocking and overlap in the same allocation, order alternating):

    mkdir -p results/raw/e7-e9
    sbatch --nodes=2 --ntasks=32 --ntasks-per-node=16 --nodelist=haskell,julia \
      --output=results/raw/e7-e9/e7_verify_%j.out \
      --export=ALL,DECOMP=blocks,REP=1,PROFILE=none,VERIFY_ONLY=1 slurm/e7_overlap.sbatch
    bash slurm/submit_e7.sh                  # REPS=5 and DECOMP=blocks by default

Both `VERIFY` lines must show `checksum=0xb8683c550fa95bd6` and each complete job ends with `PAIR COMPLETE`. Full notes: [docs/e7-e9-reproduce.md](docs/e7-e9-reproduce.md).

### E9 – Profiling

The main profile is the per-rank application timers in every MPI `RESULT` line (`t_halo`, `t_compute`, `t_reduce`, `imbalance`; for overlap also `t_post`, `t_wait`, `t_interior`, `t_boundary`); see [src/README.md](src/README.md). Optional hardware counters with `perf stat` on 1 and 32 ranks: `PROFILE=perf` in `slurm/e7_overlap.sbatch`, commands in [docs/e7-e9-reproduce.md](docs/e7-e9-reproduce.md). If `perf` or its events are not available on the node, the job says so and the timers are used instead.

### E8 – Kernel optimisation: skip tiles with no fire

`--skip-tiles T` cuts each rank's cells into T × T tiles and skips every tile with no burning cell in it or on its one-cell rim: such cells cannot change and draw no random number, so the checksum stays `0xb8683c550fa95bd6`. `make test` and `make test-mpi` compare it with the normal path (tile sizes 1, 5, 64, 5000; 1–8 ranks, strips and blocks, both overlap modes, OpenMP threads).

    DRY_RUN=1 bash slurm/submit_e8.sh      # prints the 15 sbatch commands
    bash slurm/submit_e8.sh                # submits them, waits while 8 jobs are queued

- `slurm/e8_skip_tiles.sbatch` (3 jobs, about 3 min each, haskell, 32 cores of one socket): serial without and with `--skip-tiles 32`; 32 threads without skipping and with T = 8, 16, 32, 64, 128; 1–16 threads with T = 32. Logs `e8_skip_tiles_<id>.out`.
- `slurm/e8_skip_tiles_mpi.sbatch` (12 jobs): blocks, one thread per rank, 8, 16 and 32 ranks on haskell and 32 ranks as 2 × 16 on haskell and julia; without and with `--skip-tiles 32` in the same allocation, order alternating with `REP`. Every run is checked against the E1 checksum. Logs `e8_mpi_<id>.out` (named so that the E3/E4 and E5 tools do not pick them up).

Each `RESULT` line ends with `skip_tiles=` and `active_tiles=` (share of tile updates computed). Table and figures:

    python tools/parse_logs.py results/raw > results/tables/all.csv
    python tools/plot_e8.py results/tables/all.csv results/tables results/figures

This writes `e8_summary.csv`, `e8_before_after.png`, `e8_tile_size.png` and `e8_mpi_balance.png`. `tools/make_plots.py` leaves E8 runs out of the E1/E2 figures.

Run on 22 Nov 2026 from `dd8ea11` (build job 35387, `all checks passed` and `all MPI checks passed`): serial/OpenMP jobs 35403–35405, MPI jobs 35406–35428 (12 jobs). All 63 runs gave `0xb8683c550fa95bd6`. The serial/OpenMP jobs got cores 0–31 (four whole 8-core chiplets) on a quiet node; E2 had cores 14–45 with other jobs on the node, which is why the 32-thread run without skipping is faster here (2.36 s) than in E2 (3.24 s). Compare E8 before/after only within E8.

Note: the build job now runs about 11–12 minutes because `make test-mpi` also checks `--skip-tiles`; submit it with `sbatch --time=00:20:00 slurm/build.sbatch` until PR #6 (20-minute limit in the script) is merged.

### E10 – GPU port (CUDA, OpenACC)

Code commit on `main`: `80d92af` (merge of PR 8). The runs below are on `rodrigo/e10-results`.

| | |
|---|---|
| CUDA module | `hpc-course-cuda/12.8.1` |
| OpenACC module | `nvhpc/25.7` |
| GPU | always `--gres=gpu:rtx6000ada:1` (not `rtx6000bb`) |
| Host march | `-march=znver4` (`CUDA_HOST_MARCH` in the Makefile), the march GCC 13.2 selects on haskell |
| Device | `sm_89`, `nvcc --fmad=false` |
| Binaries | `build/firefront_cuda`, `build/firefront_acc`, `build/firefront_acc_mc` |
| E1 checksum | `0xb8683c550fa95bd6` |
| CUDA build | 36548, still pending on 23 Nov (scheduler start 26 Nov 03:01). Both RTX 6000 Ada were busy |
| E1 CUDA jobs | not submitted; the build has not produced a checksum yet |
| Sweep jobs | not submitted |
| OpenACC multicore build | 36549, partition `interactive` on haskell, `acc multicore checksums ok` including E1 |
| OpenACC multicore E1 | 36550, 36551, 36552. All three print `checksum ok` and `0xb8683c550fa95bd6`. Median `t_kernel` 13.1269 s (min 13.0745, max 13.2364) |

The `cpu` partition would not start a job pinned to haskell while that node was held for the GPU partition, so 36549 and 36550–36552 were submitted with `--partition=interactive`. Same node, same binary.

On the login node (`rust`), from a checkout of this branch:

```bash
git fetch origin
git checkout rodrigo/e10-gpu
git pull origin rodrigo/e10-gpu

sbatch slurm/gpu_build.sbatch
squeue -u "$USER"
```

`results/raw/gpu_build_<id>.out` should end with `cuda checksums ok`, including `VERIFY checksum=0x74cfadfb78e73134` and `VERIFY checksum=0xb8683c550fa95bd6`. Then:

```bash
for rep in 1 2 3; do sbatch slurm/gpu.sbatch; done
```

Each log `results/raw/gpu_<id>.out` prints `checksum ok` and one `RESULT` line with `variant=cuda`, `t_kernel` (device time of the timed steps) and `t_with_copies` (that time plus the one upload and the one download). The grid stays on the GPU between steps. `--skip-tiles` is rejected.

The student QOS allows 4 running jobs and 8 submitted in total. Wait until the build has finished, then submit the three E1 jobs. After those are no longer all sitting in the queue, the size sweep, one wave at a time:

```bash
for n in 1024 2048 4096 16384; do sbatch --export=ALL,NX=$n slurm/gpu_sweep.sbatch; done
```

Repeat with `REP=2` and `REP=3`. Sizes up to 4096 are checked against `build/firefront_serial` in the same job. 16384 is timed and recorded; 8192 remains the checksum gate.

OpenACC, only after CUDA matches:

```bash
sbatch slurm/acc_build.sbatch
# then, if the log ends with "acc checksums ok":
for rep in 1 2 3; do sbatch slurm/acc.sbatch; done
```

If the GPU queue does not start, build and run OpenACC on 32 cores of haskell. That job does not ask for a GPU:

```bash
sbatch slurm/acc_mc_build.sbatch
# log ends with "acc multicore checksums ok", then:
for rep in 1 2 3; do sbatch slurm/acc_mc.sbatch; done
```

Copy the logs back to the laptop and rebuild the table and figures (no cluster needed):

```bash
python tools/plot_e10.py results/raw results/tables results/figures
```

That writes `results/tables/e10_summary.csv`, `results/figures/e10_time.png` and `results/figures/e10_speedup.png`. `tools/make_plots.py` ignores `cuda`, `acc` and `accmc` rows.

## 6. Rebuild tables and figures from the committed logs

This needs only Python and the repository; no cluster. Write into a new directory and compare with the committed files:

    pip install -r env/requirements.txt
    mkdir -p /tmp/ff/tables /tmp/ff/figures
    python tools/parse_logs.py results/raw > /tmp/ff/tables/all.csv                        # every RESULT line
    python tools/make_plots.py /tmp/ff/tables/all.csv /tmp/ff/figures                        # E1/E2 scaling, E6 size sweep
    python tools/plot_e5.py    /tmp/ff/tables/all.csv /tmp/ff/tables /tmp/ff/figures         # E5 table and figures
    python tools/plot_phase3a.py results/raw /tmp/ff/phase3a --report                        # E3, E4 tables and figures

| Output | Committed file | Rebuilt by |
|---|---|---|
| E1, E2, STREAM, E6 table | `results/tables/all.csv` | `parse_logs.py` |
| E2 figures | `results/figures/{time,speedup,efficiency,mcups}_vs_cores.png` | `make_plots.py` |
| E6 figure | `results/figures/mcups_vs_grid_size.png` | `make_plots.py` |
| E5 table and figures | `results/tables/e5_summary.csv`, `results/figures/e5_*.png` | `plot_e5.py` |
| E3, E4 tables and figures | `results/tables/e{3,4}_final{,_runs}.csv`, `results/figures/e{3,4}_report.{png,pdf}` | `plot_phase3a.py --report` (output files are named `e3.csv`, `e3_runs.csv`, …) |
| E8 table and figures | `results/tables/e8_summary.csv`, `results/figures/e8_*.png` | `plot_e8.py` |
| E10 table and figures | `results/tables/e10_summary.csv`, `results/figures/e10_time.png`, `results/figures/e10_speedup.png` | `plot_e10.py` (after the GPU logs are copied back) |
| E7 tables and figures | `results/tables/e7_{runs,summary}.csv`, `results/figures/e7_*.svg` | `python tools/analyze_e7.py results/raw/e7-e9` (needs the E7 logs, see below) |

Checked on 22 Nov 2026: `all.csv`, `e5_summary.csv`, `e3_final*.csv`, `e4_final*.csv` and `e8_summary.csv` come out identical to the committed files. (`all.csv` was regenerated on 22 Nov with the E3/E4 and E8 runs; the E2 figures committed earlier were made before the E3/E4 rows existed, so `make_plots.py` on today's `all.csv` adds those MPI runs as extra series.)

**Missing:** the raw E7 logs (`results/raw/e7-e9/`) are not in the repository yet, so the E7 table can only be checked against `results/tables/e7_runs.csv` (72 runs, job id in every row).

## 7. What every run records

- **`RESULT` line** (one per run, `key=value`): variant, grid, steps, seed, ranks, threads, `t_total` (slowest rank), cells per second, burning and burnt cells, **checksum**, **commit**, compiler version, ignitions, `OMP_PLACES`, humidity; for MPI also nodes, decomposition, process grid, overlap mode and the phase timers. `tools/parse_logs.py` reads these.
- **Environment snapshot** `results/raw/env_<jobid>.txt` (`tools/capture_env.sh`): loaded modules, compiler, CPU, Slurm variables and resources, OpenMP and MPI variables, the exact command line.
- **Node log:** node name, load and the other jobs on the node (as `self` / `other`, no user names) at start and end; `numastat` for OpenMP runs.

Logs written before commit `187c36f` contained other users' names; run `python tools/anonymize_logs.py results/raw` on such logs and check with `grep` before committing any log.
