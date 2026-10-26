# tests

    make test

- `test_model.c`: random numbers, repeatability (same seed, same checksum), burnt cells never decrease, a fire in damp conditions goes out, wind pushes the fire downwind, the fire does not cross the firebreak.
- `run_all.sh`: checks on the command line program (checksums, `RESULT` line, bad options, `--ignitions 1` keeps the old checksum, the default 1024 x 1024 / 100-step run keeps its reference checksum `0x74cfadfb78e73134`, the `humidity` field reports the value used, the fields added for MPI are present, `--overlap 1` is refused until it exists). It also builds the OpenMP version with `$OMP_CC` (default `gcc`) and checks that 1, 2, 4 and 8 threads give the serial checksum on a 512x512 grid, 100 steps, `--ignitions 16`. Without OpenMP it prints `skipped`. On a Mac: `OMP_CC=gcc-16 make test`.

- `test_decomp.c` (part of `make test`): the split of a length into pieces (contiguous, nothing lost, sizes differ by at most one) and the one-rank case.
- `make test-mpi` (needs `mpicc` and `mpirun`) runs `run_mpi.sh`:
  - `test_decomp_mpi.c`: with 1, 2, 3, 4, 6 and 8 ranks, for strips and blocks on grids that do and do not divide evenly, the blocks cover every cell exactly once and the neighbours of each rank really touch it. A grid with fewer rows than ranks must be refused by every rank.
  - `test_halo_mpi.c`: after one exchange every border cell holds the value of the global cell it stands for, corners included, and border cells outside the grid stay 0. Run twice in a row to catch stale borders.
  - The MPI program must give exactly the serial checksum for every rank count and both decompositions on five problems (default 1024 x 1024 / 100 steps, uneven 203 x 157 and 157 x 203, a flat 300 x 64 grid with wind to the north, 512 x 512 with 16 ignitions), plus one 2 ranks x 2 threads run.
  - The snapshot that rank 0 puts together from 2, 3 and 6 ranks is the same file as the serial one; with 6 ranks there is exactly one `RESULT` line, with `ranks=6`, `px=3`, `py=2`; a bad option is reported once, not once per rank.
  - Rank counts can be changed with `RANKS="2 4"`, the launcher with `MPIRUN=srun`.
  - On a Mac: `brew install open-mpi`; with OpenMP from Homebrew gcc: `OMPI_CC=gcc-16 make test-mpi`, without OpenMP: `make test-mpi MPI_OMP=`.
