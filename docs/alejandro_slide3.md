# Slide 3 · Scaling results

| E2 · Strong scaling | E4 · Weak scaling |
| :---: | :---: |
| ![OpenMP speed-up against serial E1](../results/figures/speedup_vs_cores.png) | ![Weak-scaling runtime and efficiency](../results/figures/e4_report.png) |
| **25.3× speed-up on 32 cores** | **59.1% efficiency on 32 cores** |

**E3 · One node was faster for every split.**

<!--
Speaker notes (about 40 seconds)

On the left is strong scaling. We kept the grid fixed and added cores. With 32 OpenMP threads, the simulation ran about 25 times faster than the serial version. In E3, we kept 32 cores and changed the mix of MPI ranks and OpenMP threads. One node was faster for every mix, and halo exchange took longer across two nodes.

On the right is weak scaling. We grew the grid with the core count to keep the same number of cells per core. Ideally the time would stay flat. It rose instead, and efficiency ended at 59 percent.
-->
