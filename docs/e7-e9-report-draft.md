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

Across the verified E7/E9 block-decomposition sweep, exposed communication
was highest across nodes. The medians for 32 ranks on two nodes were 0.897 s
for blocking `t_halo` and 0.368 s for overlap `t_halo`, versus 0.302 s and
0.380 s on one node. The two-node overlap wait was 0.359 s, lower than the
blocking exchange, while overlap interior updates were 5.037 s for 16 ranks
and 2.637 s for 32 ranks. Compute imbalance did not improve consistently:
the overlap median was 1.090 at 32 ranks across two nodes and 1.139 on one
node. Count-reduction maxima remained at or below 0.202 s. No rank-0 `perf`
counter run was available in the completed campaign, so E9 is reported from
the all-rank application timers rather than hardware-counter observations.

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

The complete checksum-verified SciTech sweep contains five repetitions for
each of seven block-decomposition configurations. At 4 ranks on one node, the
median runtime improved from 19.173 s blocking to 18.420 s overlap (3.93%
reduction, 1.041×). At 8 ranks the improvement was 5.46% on one node and
5.87% across two nodes. At 16 ranks, one-node overlap was 1.17% slower
(4.877 s to 4.934 s), while two-node overlap improved 7.70% (5.599 s to
5.168 s). At 32 ranks, one-node overlap was 4.87% slower (2.597 s to
2.723 s), whereas two-node overlap improved 14.07% (3.131 s to 2.690 s).
The complete range was blocking 18.550–19.237 s versus overlap 17.913–18.893 s
at 4 ranks, and blocking 3.082–3.145 s versus overlap 2.598–2.849 s at
32 ranks across two nodes.

The block layout overlaps the row phase only. Column exchange still
depends on the completed rows. MPI progress during interior work depends
on the runtime and transport. A smaller wait can coexist with unchanged
wall time or a regression if posting and boundary work consume the savings.
Progress polling or independent corner messages are follow-up experiments
if the measured wait remains high.
