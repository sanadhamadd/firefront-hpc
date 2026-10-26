#!/bin/bash
# MPI checks, run from the repository root: make test-mpi
# MPIRUN can be changed, e.g. MPIRUN="srun" inside a Slurm job.

set -u
MPIRUN=${MPIRUN:-mpirun --oversubscribe}
fail=0

for np in 1 2 3 4 6 8; do
    echo "== $np rank(s)"
    if ! $MPIRUN -np $np build/test_decomp_mpi; then
        fail=1
    fi
done

if [ $fail -eq 0 ]; then echo "all MPI checks passed"; else echo "MPI CHECKS FAILED"; fi
exit $fail
