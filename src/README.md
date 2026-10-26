# src

C sources of the simulator.

| file | what it does | status |
|---|---|---|
| `main.c` | reads the options (only rank 0 prints errors), starts MPI in the MPI build, runs the time loop with the burnt area combined every 50 steps, rank 0 prints the `RESULT` line with the slowest rank's times | done |
| `params.h/.c` | command line options and defaults | done |
| `landscape.h/.c` | synthetic fuel and elevation, built from global cell position and seed | done |
| `rules.h` | the cell rule tables (wind, slope, geometry) | done |
| `rng.h` | hash based random number per cell and step | done |
| `sim.h/.c` | grids of one rank's block (the whole grid without MPI), halo exchange then update each step (`update_block` can also do part of a block, for overlap later), per-rank halo and compute timers, counts and checksum summed over all ranks, PGM snapshot put together on rank 0 | done |
| `timers.h` | wall clock | done |
| `decomp.h/.c` | process grid (strips or blocks), each rank's block and its neighbours | done, tested with 1–8 ranks |
| `halo.h/.c` | halo exchange: rows north/south, then whole columns east/west so corners arrive (`MPI_Sendrecv`, `MPI_Type_vector`) | done, tested with 1–8 ranks |
| `step_cuda.cu`, `step_acc.c` | GPU port | to do |
| `bench/stream.c` | STREAM triad memory bandwidth (OpenMP, first touch), `make stream`, prints `RESULT variant=stream ... bw_gbs= ... places=` | done |
| `bench/` ping-pong | MPI latency and bandwidth | to do |

The grids have a border of one cell, so the same loop will work for a rank that has neighbours.

## RESULT fields added for MPI

Appended after `humidity`, so older logs and `tools/parse_logs.py` keep working:

| field | meaning |
|---|---|
| `nodes` | compute nodes the ranks ran on |
| `decomp`, `px`, `py` | strips or blocks, and the process grid (px columns x py rows of ranks); 1 x 1 without MPI |
| `overlap` | 0 = blocking halo exchange (1 is not implemented yet) |
| `t_halo`, `t_compute`, `t_reduce` | seconds in the halo exchange, in the cell updates and in the every-50-steps reductions, over the timed steps; the largest value over the ranks |
| `imbalance` | slowest rank's `t_compute` divided by the average one (1 = even) |

`t_total` is now the time of the slowest rank: all ranks start the clock together after a barrier at the end of the warm-up.
