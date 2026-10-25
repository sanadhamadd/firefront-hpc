# tests

    make test

- `test_model.c`: random numbers, repeatability (same seed, same checksum), burnt cells never decrease, a fire in damp conditions goes out, wind pushes the fire downwind, the fire does not cross the firebreak.
- `run_all.sh`: checks on the command line program (checksums, `RESULT` line, bad options, `--ignitions 1` keeps the old checksum, the default 1024 x 1024 / 100-step run keeps its reference checksum `0x74cfadfb78e73134`, the `humidity` field reports the value used). It also builds the OpenMP version with `$OMP_CC` (default `gcc`) and checks that 1, 2, 4 and 8 threads give the serial checksum on a 512x512 grid, 100 steps, `--ignitions 16`. Without OpenMP it prints `skipped`. On a Mac: `OMP_CC=gcc-16 make test`.

Halo exchange and determinism tests for different numbers of ranks will be added with the MPI code.
