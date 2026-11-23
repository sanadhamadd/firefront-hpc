# §8 Technology exploration

Draft for the report, about half a page. Every CPU number is the median of the repetitions already in `results/tables/`. The GPU cells stay empty until `results/tables/e10_summary.csv` exists; do not invent them.

<!-- serial: results/tables/all.csv, e1_baseline_24880–24882, median 81.9468 s (3 reps) -->
<!-- OpenMP 32: all.csv, e2_omp_threads_24883–24885, threads=32, places=cores, median 3.2359 s (3 reps); 81.9468/3.2359 = 25.32 -->
<!-- MPI: results/tables/e5_summary.csv, blocks, 1 node, 32 ranks, t_median 2.6198 s, speed-up 31.28 -->
<!-- hybrid: results/tables/e3_final.csv, nodes=1, 8 ranks × 4 threads, median_s 2.6936; 81.9468/2.6936 = 30.42 -->

## 8. Technology exploration

The same update runs as serial C, OpenMP, MPI, MPI+OpenMP, and, for this section, on a GPU. The GPU port is experiment E10. One kernel advances every cell, the two state grids are swapped on the device, and fuel and elevation are uploaded once. The random number is a hash of the seed, the cell and the step, so the device keeps no generator state. `nvcc --fmad=false` is the same rule as `-ffp-contract=off` on the CPU: the checksum has to match serial bit for bit (`0xb8683c550fa95bd6` on the E1 problem). OpenACC is the second version of that kernel. If the GPU queue does not run, OpenACC on 32 cores is the fallback, compared with the OpenMP row below.

Speed-up is against the serial E1 median, 81.95 s. The fastest one-node CPU result is not OpenMP. It is MPI with 32 ranks in blocks, 2.62 s, 31.3×. A useful GPU time has to beat that, not the serial run. `t_kernel` is the device time of the timed steps. `t_with_copies` adds the single upload and the single download; there is no copy per step.

| Version | Time | Speed-up | Effort | Portability | What limits it |
|---|---:|---:|---|---|---|
| Serial | 81.95 s | 1 | the reference | any C compiler | one core |
| OpenMP, 32 threads | 3.24 s | 25.3× | a parallel loop | OpenMP | memory bandwidth, and the 32-core user cap |
| MPI, 32 ranks, blocks, 1 node | 2.62 s | 31.3× | domain split and halo | MPI | halo latency; two nodes over TCP are slower (4.56 s) |
| Hybrid, 8 ranks × 4 threads, 1 node | 2.69 s | 30.4× | both of the above | MPI and OpenMP | the same halo; overlap does not remove it |
| CUDA, RTX 6000 Ada | — | — | one kernel, the rule reused | NVIDIA GPU, CUDA | device bandwidth once the grid is resident; the two copies are extra |
| OpenACC, same GPU | — | — | pragmas on that loop | NVIDIA compiler | the same bandwidth, if the compiler keeps the floating-point order |
| OpenACC, 32 CPU cores | — | — | the same source, no GPU | the NVIDIA compiler, no device | whatever OpenMP is already limited by |

<!-- Fill the empty CUDA and OpenACC cells from results/tables/e10_summary.csv: t_kernel_med, t_with_copies_med, speedup_kernel, speedup_with_copies. Median of 3, and quote min–max from the same file. -->

The CPU table is already enough to see the shape of the problem. Past 32 cores on one node the gain is in the halo, not in more threads: hybrid is slightly slower than pure MPI. The GPU does not change that arithmetic. It only helps if the resident kernel is faster than 2.62 s by enough to pay for the two transfers. Figures: `results/figures/e10_time.png` and `results/figures/e10_speedup.png`.
