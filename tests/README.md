# tests

    make test

- `test_model.c`: random numbers, repeatability (same seed, same checksum), burnt cells never decrease, a fire in damp conditions goes out, wind pushes the fire downwind, the fire does not cross the firebreak.
- `run_all.sh`: checks on the command line program (checksums, `RESULT` line, bad options).

Halo exchange and determinism tests for different numbers of ranks will be added with the MPI code.
