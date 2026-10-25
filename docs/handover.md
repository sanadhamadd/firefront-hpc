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

**STREAM triad** (same 32 cores, 12.8 GB, GB/s): 1 → 27.0, 2 → 27.1, 4 → 47.5, 8 → 35.5, 16 → 47.4, **32 → 68.0**, 64 hyper-threads → 67.7.

**Bytes per cell update, counted in `sim_step`:** a cell far from the fire reads its state byte and its fuel (4 B) and writes one state byte: **6 B** (7 B with write-allocate). A cell next to a burning one also reads its elevation (4 B): 10 B (11 B). Burning and burnt cells: 2 B (3 B). Neighbour state and elevation rows come from cache. About 98 % of the E2 cells are of the first kind, so ≈ 6 B per update: at 32 threads 8.09×10⁹ × 6 B = 48.5 GB/s, **71 % of STREAM** (62 % if write-allocate is counted on both sides). `tools/roofline.py` still defaults to the older 10-B model, which the data contradicts (it would put us at 119 % of the "maximum").

## What the checksum test guarantees

`sim_checksum` adds `mix64((global cell index << 8) | state)` over all interior cells (wrapping 64-bit sum). The order of the sum does not matter, and cell indices are global, so any split of the grid gives the same value **if and only if every cell ends in the same state** (up to a negligible chance of a hash collision). It checks the final grid only, not intermediate steps or timings.

Checked so far: serial = OpenMP for 1, 2, 4, 8 threads in `make test`; on the cluster all 24 runs of E1 and E2 (1–64 threads) gave the same checksum, also equal to a Mac build. `make test` also pins the reference `0x74cfadfb78e73134` for the default 1024² / 100-step run.

## Known issues

- **Job 24885 outliers:** 6 % slower at 1 thread (92.5 s) and 7 % at 4 threads (25.6 s). The neighbour logs show nothing special; they are only taken at the start and end of a job.
- **1-thread OpenMP is 6 % slower than serial** (87.1 vs 82.0 s), so E2 efficiencies against serial start at 0.94.
- **Shared node:** other jobs ran on haskell during all our runs (a 28–64-CPU GPU job, small CPU jobs). Times at 32 threads were tight (±0.5 %), smaller thread counts less so.
- **STREAM curve is not monotonic** (8 threads < 4). Likely each 8-core chiplet's link to memory (~27 GB/s), with our 32 cores spread unevenly over 5 chiplets; not yet verified (`lscpu -e=CPU,CORE,CACHE`).
- **numastat** in the first logs only shows a header; fixed in `slurm/job_helpers.sh`, so where the memory landed is not yet known.
- **Two MPIs:** the compute node has a system `mpirun` from Open MPI **5.0.7**; our module is **OpenMPI/4.1.6-GCC-13.2.0**. Build and run must use the module: load it in `build.sbatch` before the MPI target (today it only loads GCC) and in `hybrid.sbatch` before `srun` (done; it logs which `mpicc`/`mpirun` it uses).

## What the MPI version must keep compatible

- **RESULT line:** only **append** new fields at the end (after `humidity`), e.g. `nodes`, `t_halo`, `t_reduce`; old logs and the parser keep working. Fill `ranks` with the real number of ranks; `make_plots.py` counts cores as ranks × threads (÷ 2 for `places=threads`). Report `t_total` as the slowest rank (barrier + `MPI_Wtime`, or max-reduce).
- **Global coordinates everywhere:** `landscape_fill(..., x0, y0, ...)` takes the global position of the first interior cell; `cell_uniform` must get the **global** cell index `y * nx + x`; `sim_ignition_place(p, k, ...)` returns global positions from the seed, so every rank computes all N places and keeps the ones inside its block. `--ignite` and the default place are global too.
- **Checksum:** sum each rank's part and reduce with `MPI_SUM` on `MPI_UINT64_T` (wrapping addition is order-independent). Must equal serial: **`0xb8683c550fa95bd6` for 8192², 400 steps, `--ignitions 16`** (seed 42, other options default), and `0x74cfadfb78e73134` for the default 1024², 100 steps. Test several rank counts, including grids that do not divide evenly.
- **Logs:** keep using `slurm/job_helpers.sh` (no user or job names) and run `tools/anonymize_logs.py` on any older-format log before committing.
