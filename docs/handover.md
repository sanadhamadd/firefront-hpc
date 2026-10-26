# Handover: phase 1 (OpenMP on the cluster) → phase 2 (MPI)

From Alicia to Sanad. State of branch `omp-cluster`. Details on the cluster are in `env/cluster.md`, the job scripts are explained in `slurm/README.md`.

## Build and run on the cluster

**Never build on the login node.** It is a small virtual machine without AVX, and the Makefile uses `-march=native`. Build in a job on a compute node:

    sbatch slurm/build.sbatch      # module GCC/13.2.0; make clean, make, make omp, make stream, OMP_CC=gcc make test

Check `results/raw/build_<id>.out`: it must end with `all checks passed`, and the OpenMP lines must say `ok`, not `skipped`. On haskell gcc picks `-march=znver4`.

Then submit from the repository root (all scripts build nothing):

    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e1_baseline.sbatch; done     # serial
    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e2_omp_threads.sbatch; done  # 1..32 threads + 64 hyper-threads
    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/stream.sbatch; done          # STREAM triad
    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/size_sweep.sbatch; done      # not run yet

Rules the scripts already follow:
- **Limits of the student QOS:** 64 CPUs per user at a time = **32 physical cores** (Slurm counts both hardware threads of a core); 4 running, 8 queued jobs. An MPI run on 2 nodes may use at most **2 × 16 cores** in total.
- Build and timed jobs share the job name `firefront` with `--dependency=singleton`, so they run one at a time in submission order, and they are pinned to **haskell** (same CPU as the build).
- The cpu partition lets two jobs share cores (`OverSubscribe=FORCE:2`); `--exclusive` does not prevent it. Every job logs the node, the load and the jobs on it (as `self` / `other`, no names) at start and end.
- One repetition per job, at most 10 minutes.

**Pull pitfall.** If you copied or created logs in `results/raw/` on the cluster and the same file names are now in the repo, `git pull` stops with "untracked working tree files would be overwritten". Move them out first (they may also contain other users' names, so keep them private):

    mkdir -p ~/ff_logs && mv results/raw/*.out results/raw/env_*.txt ~/ff_logs/ 2>/dev/null
    git pull origin omp-cluster

**Collecting results:** copy the logs into `results/raw/`, then

    python tools/anonymize_logs.py results/raw          # old-format logs only; new logs have no names
    python tools/parse_logs.py results/raw > results/tables/all.csv
    python tools/make_plots.py results/tables/all.csv results/figures

and check with `grep` that no user names are left before committing.

## Measured numbers (haskell, AMD EPYC 9755, GCC 13.2.0, commit 610e539)

Problem: 8192², 400 steps (390 timed), `--ignitions 16`, seed 42. Median of 3, min–max in brackets. Data: `results/tables/all.csv`, figures in `results/figures/`.

**E1 serial:** 81.95 s (80.69–82.11) → **3.13 ns per cell update** (319 MCUPS).

**E2 OpenMP** (one thread per core, `OMP_PROC_BIND=close`, cores 14–45 on NUMA node 0), speed-up against E1:

| threads | time (s) | speed-up | efficiency |
|---|---|---|---|
| 1 | 87.14 (87.06–92.46) | 0.94 | 0.94 |
| 2 | 47.99 (47.15–48.33) | 1.71 | 0.85 |
| 4 | 23.99 (23.68–25.63) | 3.42 | 0.85 |
| 8 | 12.71 (11.89–12.74) | 6.45 | 0.81 |
| 16 | 6.40 (6.05–6.44) | 12.81 | 0.80 |
| 32 | 3.24 (3.23–3.25) | **25.32** | **0.79** (8,088 MCUPS) |
| 64 on 32 cores (hyper-threads) | 3.50 (3.49–3.52) | 23.41 | 0.73 per core |

The target (≥ 60 % efficiency at 32 cores) is met. Hyper-threads make it 8 % slower.

**STREAM triad** (12.8 GB, GB/s, median of 3), on the cores of each run:

| threads | 1 | 2 | 4 | 8 | 16 | 32 | 64 (hyper-threads) |
|---|---|---|---|---|---|---|---|
| first runs, cores 14–45 | 27.0 | 27.1 | 47.5 | 35.5 | 47.4 | **68.0** | 67.7 |
| rerun, cores 0–19 and 21–32 | 27.6 | 27.6 | 27.9 | 28.2 | 47.9 | **66.8** | 66.2 |

The rerun explains the odd first curve: each 8-core chiplet reaches only about **28 GB/s**. In the rerun, threads 1–8 all sit on one chiplet (cores 0–7), so the bandwidth stays flat until 16 threads use two; in the first runs, 4 threads already spanned two chiplets (cores 14–15 and 16–17). The limit of about **67 GB/s at 32 threads** is the same in both runs and still unexplained (it is not NUMA, see below).

**Grid size sweep** (`slurm/size_sweep.sbatch`, commit 7c686c8, 32 threads one per core, cores 0–19 and 21–32, 400 steps, 16 ignitions; MCUPS, median of 3 with min–max):

| grid | default (humidity 0.2) | `--humidity 1` (no spread) |
|---|---|---|
| 2048² | 8,129 (8,095–8,495) | 8,036 (7,959–8,170) |
| 4096² | 8,179 (8,132–8,198) | 8,157 (8,107–8,237) |
| 8192² | 7,811 (7,749–8,106) | 7,958 (7,854–8,013) |
| 16384² | 7,988 (7,971–7,998) | 7,920 (7,788–8,003) |

The default 8192² runs give the reference checksum `0xb8683c550fa95bd6`; their MCUPS are 3 % below E2 (8,088), which ran on other cores (14–45 instead of 0–32). Figure: `results/figures/mcups_vs_grid_size.png`.

**Finding: the kernel is compute-bound at 32 cores in one socket.** Throughput stays flat (within about ±2.5 %) from 2048², which fits in L3, to 16384², which streams 1.6 GB per step, and a grid with 21 % burnt (cheaper) cells is no faster. This goes against hypothesis 1 of the proposal (memory bandwidth limits thread scaling). The `--humidity 1` pass reaches 71 % of the 6-B memory limit (63 % of the 7-B limit). The 0.79 efficiency at 32 cores is therefore not memory; a likely cause is a lower clock when many cores are busy (unconfirmed; `perf stat` with cycles and task-clock would show it).

**First touch works:** with the fixed numastat logging, every sample of the sweep and the STREAM rerun shows all pages on NUMA node 0 (the socket of our cores) and 0 MB on node 1.

**Next optimisations to try:** skip tiles with no fire nearby (most cells only copy their state), and fewer branches in the neighbour check (e.g. test a whole row of neighbours at once before computing probabilities).

**Bytes per cell update, counted in `sim_step`:** a cell far from the fire reads its state byte and its fuel (4 B) and writes one state byte: **6 B** (7 B with write-allocate). A cell next to a burning one also reads its elevation (4 B): 10 B (11 B). Burning and burnt cells: 2 B (3 B). Neighbour state and elevation rows come from cache. About 98 % of the E2 cells are of the first kind, so ≈ 6 B per update: at 32 threads 8.09×10⁹ × 6 B = 48.5 GB/s, **71 % of STREAM** (62 % if write-allocate is counted on both sides). `tools/roofline.py` uses these counts: 6 B by default, and it also prints 7 B (with write-allocate, against STREAM bandwidth × 4/3) and the older 10-B model, which the data contradicts (it would put us at 119 % of the "maximum").

## What the checksum test guarantees

`sim_checksum` adds `mix64((global cell index << 8) | state)` over all interior cells (wrapping 64-bit sum). The order of the sum does not matter, and cell indices are global, so any split of the grid gives the same value **if and only if every cell ends in the same state** (up to a negligible chance of a hash collision). It checks the final grid only, not intermediate steps or timings.

Checked so far: serial = OpenMP for 1, 2, 4, 8 threads in `make test`; on the cluster all 24 runs of E1 and E2 (1–64 threads) gave the same checksum, also equal to a Mac build. `make test` also pins the reference `0x74cfadfb78e73134` for the default 1024² / 100-step run.

## Known issues

- **Job 24885 outliers:** 6 % slower at 1 thread (92.5 s) and 7 % at 4 threads (25.6 s). The neighbour logs show nothing special; they are only taken at the start and end of a job.
- **1-thread OpenMP is 6 % slower than serial** (87.1 vs 82.0 s), so E2 efficiencies against serial start at 0.94.
- **Shared node:** other jobs ran on haskell during all our runs (a 28–64-CPU GPU job, small CPU jobs). Times at 32 threads were tight (±0.5 %), smaller thread counts less so.
- **Different cores per job:** Slurm picks the 32 cores; the first jobs got 14–45, the sweep and STREAM rerun 0–19 and 21–32. Chiplet boundaries then fall differently (see STREAM), so compare runs from the same core set.
- **STREAM limit at 32 threads** (about 67 GB/s) is unexplained; the per-chiplet limit of about 28 GB/s alone would allow more.
- **numastat** in the first logs (E1, E2, first STREAM) only shows a header; fixed in `slurm/job_helpers.sh` since then.
- **Two MPIs:** the compute node has a system `mpirun` from Open MPI **5.0.7**; our module is **OpenMPI/4.1.6-GCC-13.2.0**. Build and run must use the module: load it in `build.sbatch` before the MPI target (today it only loads GCC) and in `hybrid.sbatch` before `srun` (done; it logs which `mpicc`/`mpirun` it uses).

## What the MPI version must keep compatible

- **RESULT line:** only **append** new fields at the end (after `humidity`), e.g. `nodes`, `t_halo`, `t_reduce`; old logs and the parser keep working. Fill `ranks` with the real number of ranks; `make_plots.py` counts cores as ranks × threads (÷ 2 for `places=threads`). Report `t_total` as the slowest rank (barrier + `MPI_Wtime`, or max-reduce).
- **Global coordinates everywhere:** `landscape_fill(..., x0, y0, ...)` takes the global position of the first interior cell; `cell_uniform` must get the **global** cell index `y * nx + x`; `sim_ignition_place(p, k, ...)` returns global positions from the seed, so every rank computes all N places and keeps the ones inside its block. `--ignite` and the default place are global too.
- **Checksum:** sum each rank's part and reduce with `MPI_SUM` on `MPI_UINT64_T` (wrapping addition is order-independent). Must equal serial: **`0xb8683c550fa95bd6` for 8192², 400 steps, `--ignitions 16`** (seed 42, other options default), and `0x74cfadfb78e73134` for the default 1024², 100 steps. Test several rank counts, including grids that do not divide evenly.
- **Logs:** keep using `slurm/job_helpers.sh` (no user or job names) and run `tools/anonymize_logs.py` on any older-format log before committing.

---

# Handover: phase 2 (MPI) → phase 3 (hybrid runs, overlap, profiling)

From Sanad to Alejandro and Rodrigo. State of branch `halo-exchange`, merged into `main`.

**Status.** The MPI version is written and tested on a laptop (Open MPI 5.0.11, gcc 16): it gives exactly the serial checksum for 1–16 ranks, strips and blocks, uneven grids, fires lit on rank corners, and hybrid ranks × threads. With 8 ranks the E1 problem gives `0xb8683c550fa95bd6`, the same as the serial cluster runs. **It has not run on the cluster yet** (my account is waiting for a password reset). The first person to build it there should check the build log and `slurm/mpi_check.sbatch` (below) before timing anything.

## What is new

| file | what it does |
|---|---|
| `src/decomp.c/.h` | process grid with `MPI_Cart_create`: `--decomp strips` (P × 1, whole rows) or `blocks` (`MPI_Dims_create`, the larger factor along the longer side); each rank's block, global offset and neighbours (`MPI_PROC_NULL` at the edge); uneven sizes go to the first ranks |
| `src/halo.c/.h` | halo exchange in two phases: own rows north/south, then whole columns east/west including the border rows, so corners arrive without diagonal messages; `MPI_Sendrecv`, columns as `MPI_Type_vector` |
| `src/sim.c` | each rank keeps only its block plus a one-cell border; global cell numbers for the random draws; border cells inside the grid get their real elevation (the slope term reads a burning neighbour's height); per-rank timers |
| `src/main.c` | `MPI_Init_thread(FUNNELED)`, barrier before the clock, burnt area combined every 50 steps, `t_total` = slowest rank, only rank 0 prints |
| `tests/test_decomp*.c`, `tests/test_halo_mpi.c`, `tests/run_mpi.sh` | `make test-mpi`: split, halo (corners included) and checksum vs serial on 1, 2, 3, 4, 6, 8 ranks, snapshots, RESULT fields |
| `slurm/mpi_check.sbatch` | which launcher works with the OpenMPI module (srun default / pmi2 / pmix, mpirun) |
| `slurm/e5_decomp.sbatch`, `slurm/submit_e5.sh` | E5 and the MPI part of E2 (51 jobs), waits when 8 jobs are queued |
| `slurm/hybrid.sbatch` | E3 hybrid split, `--overlap 0`, same problem as E1, prints `checksum ok` |

New RESULT fields (appended after `humidity`): `nodes decomp px py overlap t_halo t_compute t_reduce imbalance`. The three times are the largest value over the ranks; `t_halo` includes waiting for a slower neighbour. `imbalance` is the slowest rank's compute time over the average one. Details in `src/README.md`.

## Build and first run on the cluster

    sbatch slurm/build.sbatch          # now also: make mpi, make test-mpi (up to 8 ranks)
    sbatch slurm/mpi_check.sbatch
    sbatch --nodes=2 --ntasks-per-node=2 --nodelist=haskell,julia slurm/mpi_check.sbatch

The build log must end with `all checks passed` and `all MPI checks passed`. The end of each `mpi_check` log lists every launcher as `works` or `fails`; pass the first one that works as `LAUNCH=...` to the job scripts (default `srun --cpu-bind=cores`). The two-node check also shows whether julia can run the binary built on haskell (`-march=native`); if it cannot, build with a CPU both nodes have, e.g. `make NATIVE=-march=znver4 mpi`.

## Alejandro: hybrid runs (E3, E4, E6)

`build/firefront_mpi` is the hybrid program: ranks from Slurm, threads from `OMP_NUM_THREADS`. Example, 2 nodes × 4 ranks × 4 cores:

    sbatch --nodes=2 --ntasks-per-node=4 --cpus-per-task=4 --export=ALL,DECOMP=blocks,REP=1 slurm/hybrid.sbatch

One node needs `--nodelist=haskell` on the command line (the script defaults to both nodes). With `--hint=nomultithread` every CPU of `--cpus-per-task` is a whole core, so ranks × threads ≤ 32 in total. `make_plots.py` already counts cores as ranks × threads; runs are grouped by variant, so MPI runs form their own series. Weak scaling (E4) only needs `NX` set per job, e.g. `--export=ALL,NX=4096,...`.

## Rodrigo: overlap (E7) and profiling (E8, E9)

The hook is `update_block(s, r0, r1, c0, c1, step)` in `src/sim.c`: it updates any rectangle of own cells (rows r0..r1, columns c0..c1, local, 1 = first own cell), with OpenMP inside. `sim_step` today does:

    halo_exchange(...);                          /* blocking, timed as t_halo */
    update_block(s, 1, ny, 1, nx, step);         /* whole block, timed as t_compute */

For overlap: start the exchange with `MPI_Irecv`/`MPI_Isend` (add a `halo_start`/`halo_finish` pair in `halo.c`), call `update_block` for the inner cells `2..ny-1 × 2..nx-1`, wait, then call it for the four strips of the boundary ring. The two-phase corner trick needs the rows before the columns, so with non-blocking messages either keep two phases or send the four corners as extra messages. `--overlap` is already parsed and printed in the RESULT line; today `--overlap 1` is refused in `params.c`, so remove that check when the code exists. The checksum must stay the same as with `--overlap 0`; `make test-mpi` shows that quickly.

Timers for the analysis: `t_halo` vs `t_compute` per run, and `imbalance`. With overlap, time only the wait as `t_halo`, so the before/after comparison shows how much communication was hidden.

## Known issues

- Not yet run on the cluster: launcher, OpenMPI 4.1.6 behaviour and julia's CPU are unchecked.
- `--snapshot` with MPI gathers the whole picture on rank 0; fine for pictures, not for timed runs.
- On a Mac, the MPI build without Homebrew gcc has no OpenMP: `make test-mpi MPI_OMP=`, or `OMPI_CC=gcc-16 make test-mpi` for the hybrid build.

## Measured numbers

To be added after E5 runs (strips vs blocks, 1 and 2 nodes, MPI strong scaling).
