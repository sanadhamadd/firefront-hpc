#!/bin/bash
# MPI checks, run from the repository root: make test-mpi
#   1. the grid split (test_decomp_mpi) and the halo exchange (test_halo_mpi) on 1..8 ranks;
#   2. the MPI program must give exactly the serial checksum for every rank count and both
#      decompositions, on grids that do and do not divide evenly.
# MPIRUN can be changed, e.g. MPIRUN="srun" inside a Slurm job.

set -u
MPIRUN=${MPIRUN:-mpirun --oversubscribe}
RANKS=${RANKS:-1 2 3 4 6 8}
fail=0

for np in $RANKS; do
    echo "== split and halo, $np rank(s)"
    # the split test also tries a grid that is too small on purpose; its refusal message goes to stderr
    $MPIRUN -np $np build/test_decomp_mpi 2>/dev/null | grep -v '^ok' || true
    $MPIRUN -np $np build/test_decomp_mpi > /dev/null 2>&1 || fail=1
    $MPIRUN -np $np build/test_halo_mpi | grep -v '^ok' || true
    $MPIRUN -np $np build/test_halo_mpi > /dev/null || fail=1
done
[ $fail -eq 0 ] && echo "ok:   split and halo tests on ranks: $RANKS"

checksum() {
    grep '^RESULT' | sed 's/.*checksum=\(0x[0-9a-f]*\).*/\1/'
}

# several problems: default size, uneven sizes, more ignitions, other wind, very flat grids
cases=(
    "--nx 1024 --ny 1024 --steps 100"
    "--nx 203 --ny 157 --steps 150 --ignitions 7"
    "--nx 157 --ny 203 --steps 150 --ignitions 7 --seed 3"
    "--nx 300 --ny 64 --steps 200 --ignitions 5 --wind-dir 90 --wind-speed 10"
    "--nx 512 --ny 512 --steps 100 --ignitions 16 --humidity 0.4"
)

export OMP_NUM_THREADS=1
for args in "${cases[@]}"; do
    want=$(build/firefront_serial $args | checksum)
    for np in $RANKS; do
        for decomp in strips blocks; do
            got=$($MPIRUN -np $np build/firefront_mpi $args --decomp $decomp 2>/dev/null | checksum)
            if [ "$got" != "$want" ]; then
                echo "FAIL: $np rank(s), $decomp, $args: $got, serial $want"
                fail=1
            fi
        done
    done
    echo "checked: $args (serial $want)"
done

# hybrid: 2 ranks x 2 threads must also match, if the build has OpenMP
args="--nx 203 --ny 157 --steps 150 --ignitions 7"
want=$(build/firefront_serial $args | checksum)
got=$(OMP_NUM_THREADS=2 $MPIRUN -np 2 build/firefront_mpi $args 2>/dev/null | checksum)
if [ "$got" = "$want" ]; then echo "ok:   2 ranks x 2 threads gives the serial checksum"; else echo "FAIL: 2 ranks x 2 threads: $got, serial $want"; fail=1; fi

if [ $fail -eq 0 ]; then echo "all MPI checks passed"; else echo "MPI CHECKS FAILED"; fi
exit $fail
