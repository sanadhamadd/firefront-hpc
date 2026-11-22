# Report draft: sections 1, 2 and 4

Draft by Alicia. Section 3 (HPC implementation) is Sanad's; section 2 describes the model and the code, and leaves OpenMP, MPI and the halo exchange to section 3. Page budget: §1 ≈ 0.5 page, §2 ≈ 0.75 page, §4 ≈ 0.75 page. Every number below is taken from `results/tables/` or `docs/handover.md`.

---

## 1. Problem and motivation

FireFront-HPC simulates how a wildfire spreads across a landscape. Spain had one of its worst fire seasons in 2025, and fire-spread forecasts are only useful if they are both fine-grained and fast. Two things make the problem expensive. First, resolution: going from 100 m to 25 m cells multiplies the number of cells by 16, and because the fire needs about 4× more time steps to cover the same distance, the work for the same simulated time grows by about 64×. Second, uncertainty: wind and humidity are not known exactly, so a useful forecast runs hundreds of weather scenarios, not one.

We model the fire as a cellular automaton on a raster grid. Its update is simple and local, like a stencil code, which makes it a clean test case for the HPC techniques of this course: thread parallelism, domain decomposition, halo exchange and the balance between computation and communication.

**Size of the problem.** Our test case is an 8192 × 8192 grid (67 million cells of 25 m, a 205 × 205 km area) for 400 time steps: about 27 billion cell updates and 0.67 GB of data. The serial program needs 82 s for it. All of Spain at 25 m would be about 8 × 10⁸ cells per scenario.

**Expected challenges.** (1) A halo exchange every step with small messages (one 8192-cell row is 8 KB), so latency and the choice of decomposition matter. (2) A branch-heavy kernel: each cell checks eight neighbours with data-dependent branches, which limits vectorisation. (3) Irregular work: the fire covers only a few percent of the grid. (4) Results must be identical for any number of threads or ranks, on a shared cluster where timings are noisy.

**Success criteria** (set in the proposal). Every parallel version reproduces the serial result bit for bit; all experiments can be rerun from `REPRODUCE.md`; the main bottleneck is explained with timer or counter evidence; and, as a performance goal, at least 60 % parallel efficiency on 32 cores.

## 2. Application architecture

**Model.** Every cell holds a state byte (unburnt; burning for 1…B steps; or burnt), a fuel load and an elevation. At each step, every burning neighbour *d* of an unburnt cell contributes an ignition probability

p_d = min(1, p₀ (1 − H) · fuel · f_wind,d / dist_d · f_slope,d),

and the cell ignites with probability p = 1 − ∏_d (1 − p_d). Here H is the humidity, f_wind = exp(c_w V (cos θ − 1)) is largest when the fire spreads straight downwind (V is the wind speed, θ the angle between the wind and the direction of spread), and f_slope = exp(c_s Δh / (dist · cell size)) favours spread uphill. A burning cell burns for B = 3 steps and then burns out. Defaults: p₀ = 0.8, H = 0.2, wind 6 m/s towards the east, 25 m cells, and a three-cell river with no fuel that acts as a firebreak. Timed runs start the fire at 16 points placed from the seed (`--ignitions 16`), so that a meaningful part of the grid is active.

*Place Figure 1 here:* `docs/img/c_fire_front.png`. **Caption.** Output of the serial code (400 × 400 cells, one ignition, wind towards the east). The fire spreads mainly downwind and stops at the river (blue).

**Algorithm.** The update is *dense*: every cell is visited at every step, and the new state is written to a second buffer (double buffering), so the result does not depend on the order of the updates. The wind and slope factors are pre-computed in small tables, so the inner loop contains no `exp()` call. Far from the fire, a cell update reads one state byte and the fuel value (4 B) and writes one state byte, about 6 bytes per update; this count is used for the roofline bound in sections 4 and 6.

**Reproducibility by design.** Three choices make the result independent of how the grid is split. (1) Random numbers come from a SplitMix64 hash of (seed, global cell index, step) instead of a random-number stream, so each cell's random draw is the same whichever thread or rank updates it. (2) Fuel and elevation are smooth noise computed from the global cell position and the seed, so each process builds its own part of the landscape without reading a file. (3) The grid has a one-cell border, so the same update loop works for the whole grid or for one rank's block with halo cells. All builds use `-ffp-contract=off`, so the floating-point operations are the same in every version.

**Verification.** At the end of a run, the program computes a checksum: a wrapping 64-bit sum of a hash of (global cell index, final state) over all cells. The sum does not depend on the order of addition, so any split of the grid gives the same value if and only if every cell ends in the same state. Every parallel run must reproduce the serial checksum (`0xb8683c550fa95bd6` for the test case) before its time is used. `make test` also checks plausibility: the same seed gives the same result, burnt cells never decrease, a damp fire goes out, wind pushes the fire downwind and the fire does not cross the river. These are sanity checks, not a physical validation of the model.

**Code structure.** One C11 code base builds the serial, OpenMP and MPI + OpenMP versions (`make`, `make omp`, `make mpi`).

| Component | Role |
|---|---|
| `params.c` | command-line options and defaults |
| `landscape.c` | synthetic fuel and elevation from global coordinates |
| `rules.h`, `rng.h` | wind/slope tables; hash-based random numbers |
| `sim.c` | state grids, the cell update, timers, checksum, snapshots |
| `decomp.c`, `halo.c` | MPI process grid and halo exchange (section 3) |
| `main.c` | time loop, warm-up, the `RESULT` line |

*Place Figure 2 here (optional, if space):* `docs/img/software_structure.png`.

Each run prints one `RESULT key=value` line with the configuration, the timings, the checksum and the git commit. Python scripts in `tools/` parse these lines into CSV tables and plots. A NumPy prototype (`tools/prototype/`) was used to test the rules before the C code.

## 4. Experimental methodology

**Cluster.** All timed runs ran on the SciTech cluster through Slurm (`sbatch`/`srun`). We used two compute nodes: *haskell*, with 2 × AMD EPYC 9755 (Zen 5, 128 cores each, 2 hardware threads per core), and *julia*, with 2 × AMD EPYC 9745. Each socket is one NUMA domain, and its cores are grouped in 8-core chiplets that each have their own 32 MB L3 cache. The student QOS limits us to 64 CPUs, i.e. **32 physical cores**, at a time, so two-node runs use 2 × 16 cores.

**Software.** GCC 13.2.0 with `-O3 -march=native -ffp-contract=off`; Open MPI 4.1.6 built with the same GCC. Open MPI's default network layer (UCX) crashed at start-up in some two-node runs, so all MPI runs use the `ob1` layer with shared memory within a node and TCP between nodes, on one node too, so that all MPI timings use the same path.

**Workload.** Unless stated otherwise, every run uses the 8192 × 8192 grid, 400 steps, 16 ignition points and seed 42. The first 10 steps are an untimed warm-up, so 390 steps are timed.

**Placement.** OpenMP threads are pinned one per core (`OMP_PROC_BIND=close`, `OMP_PLACES=cores`) on one socket; MPI ranks are bound to cores (`srun --cpu-bind=cores`, `--hint=nomultithread`). Memory is initialised by the threads that use it (first touch); `numastat` confirmed that all pages were on the socket of our cores. One-node runs use haskell; two-node runs use haskell and julia.

**Measurements.** Wall time is measured with a monotonic clock around the timed steps; for MPI runs, after a barrier, and the reported time is that of the slowest rank. From it we derive:

- **speed-up** = serial E1 median (81.95 s) / time, and **parallel efficiency** = speed-up / physical cores;
- **throughput** in million cell updates per second (MCUPS);
- for MPI: the time in halo exchange, in cell updates and in reductions, each as the maximum over the ranks, and the **compute imbalance** (slowest rank's compute time / average);
- **weak-scaling efficiency** = time on 1 core / time on N cores at constant cells per core;
- **memory bandwidth** with the STREAM triad benchmark on the same 32 cores, used as a roofline bound (bandwidth / 6 B per update).

Because phase maxima can come from different ranks, they cannot be added up to give the wall time. The halo time also includes time spent waiting for a slower neighbour.

**Experiments.**

| # | Question | Configurations | Reps |
|---|---|---|---|
| E1 | Baseline | serial, 1 core | 3 |
| E2 | Strong scaling | OpenMP 1–32 threads (+ 64 on hyper-threads); MPI 1–32 ranks | 3 |
| E3 | Hybrid split | 32 cores as 8 × 4, 16 × 2, 32 × 1 ranks × threads; 1 and 2 nodes | 3 |
| E4 | Weak scaling | 1024² cells per core on 1, 4, 16, 32 cores | 3 |
| E5 | Sensitivity: decomposition | strips vs blocks, 1–32 ranks, 1 and 2 nodes | 3 |
| E6 | Sensitivity: grid size | 2048²–16384² at 32 threads, with and without fire spread | 3 |
| E7 | Optimisation | blocking vs overlapped halo exchange, 4–32 ranks, 1 and 2 nodes | 5 pairs |
| E8 | Optimisation 2 | skip tiles with no fire (`--skip-tiles T`): serial, 32 threads, MPI 8–32 ranks; T = 8–128 | 3 |
| E9 | Profiling | application and MPI timers in every run; `perf stat` where available | — |
| E10 | Additional technology | GPU (CUDA, OpenACC) vs best 32-core CPU run | 3 |
| — | Memory bandwidth | STREAM triad, 1–32 threads | 3 |

*Update the E9 and E10 rows to what was finally run before the freeze. E8 before/after runs share a job (serial/OpenMP) or an allocation (MPI), like E7.*

**Repetitions and noise.** Each Slurm job runs one repetition, so repetitions get independent allocations, and every job is limited to 10 minutes. We report the median with the minimum and maximum. Our own timed jobs never ran at the same time (`--dependency=singleton`), but the partition lets other users' jobs share cores (`OverSubscribe=FORCE:2`) and this cannot be turned off; each job therefore logs the load and the other jobs on its node at the start and end. For E7, blocking and overlap run in the same allocation with alternating order, so both modes see the same conditions.

**Limitations.** (1) Slurm chooses which 32 cores a job gets; the first OpenMP jobs got cores 14–45, later ones 0–19 and 21–32, and chiplet boundaries then fall differently, so we only compare runs that used the same core set. (2) Two-node runs use TCP, not the faster UCX path, so they show a pessimistic communication cost. (3) The same two-node configuration (32 ranks, blocks) took 4.56 s in the E5 campaign and 3.13–3.14 s in the later E3 and E7 campaigns, with the same MPI code and transport. We did not identify the cause, so two-node results are compared only within one campaign. Placement and node load matter on one node too: the 32-thread run without skipping took 3.24 s in E2 (cores 14–45, other jobs on the node) but 2.36 s in the E8 campaign (cores 0–31, four whole chiplets, a quiet node); E8 therefore compares before and after only within the same job. (4) The 32-core limit means our largest runs use one eighth of a node.

All commands, module versions and job scripts are in `REPRODUCE.md`; every `RESULT` line carries the git commit of the binary that produced it.
