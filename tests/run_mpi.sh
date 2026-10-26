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

# snapshot: the picture rank 0 puts together must be the same file as the serial one
tmp=$(mktemp -d)
args="--nx 403 --ny 301 --steps 150 --ignitions 9"
build/firefront_serial $args --snapshot "$tmp/serial.pgm" > /dev/null
same=1
for np in 2 3 6; do
    for decomp in strips blocks; do
        $MPIRUN -np $np build/firefront_mpi $args --decomp $decomp --snapshot "$tmp/mpi.pgm" > /dev/null 2>&1
        cmp -s "$tmp/serial.pgm" "$tmp/mpi.pgm" || { echo "FAIL: snapshot with $np ranks, $decomp differs"; same=0; fail=1; }
    done
done
rm -rf "$tmp"
[ $same -eq 1 ] && echo "ok:   snapshots from 2, 3 and 6 ranks equal the serial one"

# RESULT line: real rank count and process grid, and only rank 0 prints it
line=$($MPIRUN -np 6 build/firefront_mpi --nx 300 --ny 200 --steps 30 --decomp blocks 2>/dev/null)
n=$(echo "$line" | grep -c '^RESULT')
fields=""
for key in ranks decomp px py; do
    fields="$fields$(echo "$line" | grep '^RESULT' | tr ' ' '\n' | grep "^$key=") "
done
check_line="ranks=6 decomp=blocks px=3 py=2 "
if [ "$n" = "1" ] && [ "$fields" = "$check_line" ]; then
    echo "ok:   one RESULT line with ranks=6, blocks, 3 x 2 process grid"
else
    echo "FAIL: RESULT lines: $n, fields: $fields (want $check_line)"; fail=1
fi

# a bad option is reported once, not once per rank
n=$($MPIRUN -np 4 build/firefront_mpi --decomp diagonal 2>&1 | grep -c 'must be strips or blocks')
if [ "$n" = "1" ]; then echo "ok:   a bad option is reported once"; else echo "FAIL: bad option reported $n times"; fail=1; fi

if [ $fail -eq 0 ]; then echo "all MPI checks passed"; else echo "MPI CHECKS FAILED"; fi
exit $fail
