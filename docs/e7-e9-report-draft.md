# FireFront-HPC report draft

## 6. Bottleneck Analysis

We used monotonic application timers to measure the simulation loop and its
MPI exchange, cell update and periodic count reductions. At 400 steps the
first 10 were warm-up. Each phase was summed on each rank and reported as
the maximum across ranks. Compute imbalance is the maximum rank compute
time divided by the average. Phase maxima can occur on different ranks, so
they cannot be stacked to reconstruct wall time.

The completed blocking E5 experiments show that the dominant cost changes
with node count. For 32 single-threaded ranks with block decomposition,
median time increased from 2.62 s on haskell to 4.56 s across haskell and
julia. At that configuration, maximum-rank halo time was approximately
0.29 s on one node and 2.20 s on two nodes. Across the two-node E5 sweep, the
halo-time-to-runtime ratio ranged from 43% to 56%, and compute imbalance rose
to about 1.5 compared with about 1.05 on one node. The count-reduction phase
was much smaller. The independently timed 8-rank julia control was close to
the haskell result (10.72 s versus 10.54 s), so the node CPU difference alone
offers little explanation for the two-node penalty. See
`results/tables/e5_summary.csv`, `results/figures/e5_efficiency_halo.png` and
`results/raw/e5_checks/`.

The two-node jobs used TCP after startup failures with the default UCX PML.
The timers support exposed halo communication and neighbor waiting as a
major two-node bottleneck. They cannot distinguish network transfer time
from waiting for ranks that reach the exchange later. The limited UCX runs
that started were faster at eight ranks, but mixed startup reliability
prevents a controlled sweep across transports. The one-node case spent
most of its time updating cells, and these timers alone cannot determine
whether memory bandwidth or instruction throughput limits that kernel.

[PENDING: E9 medians for exposed MPI time, cell updates, reductions and
compute imbalance. Cite the E7 communication and imbalance figures.
Include rank 0 perf observations only if counters ran successfully.]

## 7. Optimization

The blocking implementation exchanges north/south rows, then east/west
columns that include the newly received rows. We targeted the halo exchange
because E5 showed high exposed communication cost across nodes. The overlap
mode posts receives and sends for the first phase, updates the interior
from the old state into the new state, then waits for the requests. When
there are both row and column neighbors, it posts columns only after rows
arrive, so the columns still forward the diagonal corner cells. It waits
before updating the boundary ring. A narrow block with an empty interior
updates its entire local grid once after communication. MPI calls stay on
the main thread.

Local tests with Open MPI 4.1.6 matched the serial checksum across both
decompositions at 1, 2, 3, 4, 6 and 8 ranks and compared halo cells and
snapshots. The SciTech correctness gate requires both modes to reproduce checksum
`0xb8683c550fa95bd6` before each paired job takes timings. The benchmark
uses the same binary and Slurm allocation for both modes. Execution order
alternates across five repetitions per configuration. The timers distinguish
interior and boundary work, MPI posting, and completion wait. End-to-end
runtime captures any additional OpenMP worksharing and communication
bookkeeping.

[PENDING: SciTech reference check and median blocking versus overlap runtime,
min–max, optimization speedup and runtime reduction for one and two nodes.
Cite the E7 runtime and speedup figures. Identify which configurations
regressed or improved and compare the measured post/wait and compute times.]

The block layout overlaps the row phase only. Column exchange still
depends on the completed rows. MPI progress during interior work depends
on the runtime and transport. A smaller wait can coexist with unchanged
wall time or a regression if posting and boundary work consume the savings.
Progress polling or independent corner messages are follow-up experiments
if the measured wait remains high.
