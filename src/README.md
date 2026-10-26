# src

C sources of the simulator.

| file | what it does | status |
|---|---|---|
| `main.c` | reads the options, starts MPI in the MPI build, runs the time loop, rank 0 prints the `RESULT` line | done; MPI timers and extra RESULT fields still to add |
| `params.h/.c` | command line options and defaults | done |
| `landscape.h/.c` | synthetic fuel and elevation, built from global cell position and seed | done |
| `rules.h` | the cell rule tables (wind, slope, geometry) | done |
| `rng.h` | hash based random number per cell and step | done |
| `sim.h/.c` | grids of one rank's block (the whole grid without MPI), halo exchange then update each step (`update_block` can also do part of a block, for overlap later), counts and checksum summed over all ranks, PGM snapshot (one rank only for now) | done |
| `timers.h` | wall clock | done |
| `decomp.h/.c` | process grid (strips or blocks), each rank's block and its neighbours | done, tested with 1–8 ranks |
| `halo.h/.c` | halo exchange: rows north/south, then whole columns east/west so corners arrive (`MPI_Sendrecv`, `MPI_Type_vector`) | done, tested with 1–8 ranks |
| `step_cuda.cu`, `step_acc.c` | GPU port | to do |
| `bench/stream.c` | STREAM triad memory bandwidth (OpenMP, first touch), `make stream`, prints `RESULT variant=stream ... bw_gbs= ... places=` | done |
| `bench/` ping-pong | MPI latency and bandwidth | to do |

The grids have a border of one cell, so the same loop will work for a rank that has neighbours.
