## 5. Results

We report the median of three runs per configuration, with the minimum and maximum showing the spread. All 30 runs used simulator commit `ce2e211` and matched the serial checksum for their grid. Each run simulated 400 steps. We timed 390 steps after a 10-step warm-up.

**Hybrid MPI/OpenMP (E3).** We kept the 8192 × 8192 grid and 32 physical cores fixed and changed the number of MPI ranks and OpenMP threads. On one node, the best median was 2.694 s with 8 ranks and 4 threads per rank, close to 2.699 s with 16 ranks and 2 threads. For the same splits, two nodes took 14.4–23.2% longer than one node. The best two-node median was 3.137 s with 32 ranks and one thread per rank. Median halo time rose from 0.363–0.418 s on one node to 0.801–0.927 s on two. Halo exchanges send boundary cells between neighboring ranks. On two nodes, some exchanges cross the network. The longer halo times help explain the slowdown, but the timer also includes time spent waiting for neighbors.

*Place Figure E3 here.* [Hybrid runtime and halo exchange](../results/figures/e3_report.pdf). **Caption.** Median runtime (a) and halo time (b) for each 32-core split. Bars show the minimum and maximum of three runs. Halo time is the longest time any rank spent in halo exchanges within a run.

**Weak scaling (E4).** We grew the grid from 1024 × 1024 to 8192 × 4096 while keeping 1024² cells per physical core. Median runtime rose from 1.120 s on one core to 1.289, 1.406, and 1.895 s on 4, 16, and 32 cores. Efficiency fell to 86.9%, 79.7%, and 59.1%, respectively. At four cores, efficiency had already fallen with one MPI rank and no measured halo time. Median halo time reached 0.135 s at 16 cores and 0.595 s at 32 cores, consistent with more time spent exchanging data and waiting. The 32-core case also moved to two nodes, so we cannot tell how much of the slowdown came from the network alone. Runtime also varied more between repetitions at 16 and 32 cores.

*Place Figure E4 here.* [Weak-scaling runtime and efficiency](../results/figures/e4_report.pdf). **Caption.** Median runtime (a) and weak-scaling efficiency (b). Runtime bars show the minimum and maximum of three runs. Efficiency is the one-core median divided by the median at each core count. Dashed lines show ideal weak scaling.

*Replace “Figure E3” and “Figure E4” with their final numbers in the shared report.*
