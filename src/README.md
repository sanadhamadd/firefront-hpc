# src

C sources of the simulator.

| file | what it does | status |
|---|---|---|
| `main.c` | reads the options, runs the time loop, prints the `RESULT` line | done |
| `params.h/.c` | command line options and defaults | done |
| `landscape.h/.c` | synthetic fuel and elevation, built from global cell position and seed | done |
| `rules.h` | the cell rule tables (wind, slope, geometry) | done |
| `rng.h` | hash based random number per cell and step | done |
| `sim.h/.c` | grids, one time step, counts, checksum, PGM snapshot | done (serial, OpenMP pragma in place, not yet tried on the cluster) |
| `timers.h` | wall clock | done |
| `decomp.c`, `halo.c` | process grid and halo exchange (MPI) | to do |
| `step_cuda.cu`, `step_acc.c` | GPU port | to do |
| `bench/` | ping-pong and bandwidth benchmarks | to do |

The grids have a border of one cell, so the same loop will work for a rank that has neighbours.
