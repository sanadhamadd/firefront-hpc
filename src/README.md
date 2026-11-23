# src

C sources of the simulator.

| file | what it does | status |
|---|---|---|
| `main.c` | reads the options (only rank 0 prints errors), starts MPI in the MPI build, runs the time loop with the burnt area combined every 50 steps, rank 0 prints the `RESULT` line with the slowest rank's times | done |
| `params.h/.c` | command line options and defaults | done |
| `landscape.h/.c` | synthetic fuel and elevation, built from global cell position and seed | done |
| `rules.h` | the cell rule tables (wind, slope, geometry) | done |
| `rng.h` | hash based random number per cell and step | done |
| `sim.h/.c` | local state grids, blocking and overlapped step paths, per-rank phase timers, distributed counts and checksum, PGM snapshot gathered on rank 0 | done |
| `timers.h` | wall clock | done |
| `decomp.h/.c` | process grid (strips or blocks), each rank's block and its neighbours | done, tested with 1–8 ranks |
| `halo.h/.c` | blocking and nonblocking halo exchange: rows first, then whole columns forwarding the corners, using an MPI vector datatype | done |
| `update.h` | the cell rule, shared by the CPU loops and the GPU builds | done |
| `ignite.c` | where the extra ignition patches go; same function for every build | done |
| `rules_build.c` | builds the wind and slope tables once, with the CPU compiler | done |
| `step_cuda.cu` | CUDA: one kernel per step, double buffer, grid stays on the device | code done; the cluster job checks the checksum |
| `step_acc.c` | OpenACC GPU and multicore, same step | code done; the cluster job checks the checksum |
| `bench/stream.c` | STREAM triad memory bandwidth (OpenMP, first touch), `make stream`, prints `RESULT variant=stream ... bw_gbs= ... places=` | done |
| `bench/` ping-pong | MPI latency and bandwidth | to do |

The grids have a border of one cell, so the same loop will work for a rank that has neighbours.

## RESULT fields added for MPI

Appended after `humidity`, so older logs and `tools/parse_logs.py` keep working:

| field | meaning |
|---|---|
| `nodes` | compute nodes the ranks ran on |
| `decomp`, `px`, `py` | strips or blocks, and the process grid (px columns x py rows of ranks); 1 x 1 without MPI |
| `overlap` | 0 = blocking halo exchange, 1 = overlap the first active phase with interior updates (MPI only) |
| `t_halo` | full blocking exchange time or, in overlap mode, exposed MPI posting plus waiting time |
| `t_compute`, `t_reduce` | time updating cells and time in the periodic counts and reductions |
| `imbalance` | slowest rank's `t_compute` divided by the average one (1 = even) |
| `t_post`, `t_wait`, `t_interior`, `t_boundary` | overlap-only fields for request posting, completion calls, interior and boundary updates |
| `skip_tiles` | E8: tile edge T of `--skip-tiles T` (0 = every cell is updated); printed by every build |
| `active_tiles` | E8: share of the tile updates that were computed, over all ranks and timed steps (1 with `skip_tiles=0`) |
| `t_kernel` | GPU builds only: device time of the timed steps (CUDA events, or the OpenACC loops) |
| `t_with_copies` | GPU builds only: `t_kernel` plus the one upload of the grids and the one download of the state |

`t_total` is the slowest rank's time after the warm-up barrier. Each phase is
summed locally over the timed steps and then maximized across ranks. The maxima
can refer to different ranks. Use `--verify-only` to run the same steps and
emit a `VERIFY checksum=...` line without collecting or reporting timings.
