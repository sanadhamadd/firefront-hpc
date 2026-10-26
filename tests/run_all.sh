#!/bin/bash
# Command line checks on the built binary. The model checks are in test_model.c.
# Run from the repository root (make test does this).

set -u
bin=build/firefront_serial
fail=0

check() {
    if [ "$2" = "$3" ]; then
        echo "ok:   $1"
    else
        echo "FAIL: $1 ($2 vs $3)"
        fail=1
    fi
}

checksum() {
    "$bin" "$@" | grep '^RESULT' | sed 's/.*checksum=\(0x[0-9a-f]*\).*/\1/'
}

args="--nx 200 --ny 150 --steps 120 --seed 7"

a=$(checksum $args)
b=$(checksum $args)
check "two runs give the same checksum" "$a" "$b"

c=$(checksum --nx 200 --ny 150 --steps 120 --seed 8)
if [ "$a" != "$c" ]; then echo "ok:   another seed changes the checksum"; else echo "FAIL: seed has no effect"; fail=1; fi

line=$("$bin" $args | grep '^RESULT')
missing=""
for field in variant nx ny steps seed ranks threads t_total cells_per_s burning burnt checksum commit compiler ignitions places humidity nodes decomp px py overlap t_halo t_compute t_reduce imbalance; do
    case "$line" in
        *" $field="*) ;;
        *) missing="$missing $field" ;;
    esac
done
if [ -z "$missing" ]; then echo "ok:   RESULT line has all fields"; else echo "FAIL: RESULT line has no$missing"; fail=1; fi

if "$bin" --nx 2 >/dev/null 2>&1; then echo "FAIL: tiny grid was accepted"; fail=1; else echo "ok:   tiny grid is rejected"; fi
if "$bin" --ignitions 0 >/dev/null 2>&1; then echo "FAIL: --ignitions 0 was accepted"; fail=1; else echo "ok:   --ignitions 0 is rejected"; fi

d=$(checksum $args --ignitions 1)
check "--ignitions 1 gives the same checksum as before" "$a" "$d"

# reference checksum of the default model, recorded before fields were appended to the
# RESULT line; it must never change unless the model itself is changed on purpose
ref=$(checksum --nx 1024 --ny 1024 --steps 100)
check "default 1024 x 1024, 100 steps keeps its reference checksum" "0x74cfadfb78e73134" "$ref"

if "$bin" --overlap 1 >/dev/null 2>&1; then echo "FAIL: --overlap 1 was accepted"; fail=1; else echo "ok:   --overlap 1 is refused until it exists"; fi

h=$("$bin" --nx 64 --ny 64 --steps 5 --humidity 0.4 | grep '^RESULT' | sed 's/.* humidity=\([^ ]*\).*/\1/')
check "RESULT line reports the humidity used" "0.4" "$h"

# OpenMP must give the serial checksum for any number of threads.
# The compiler comes from OMP_CC (default gcc); -B rebuilds so the binary really comes from it.
omp_cc=${OMP_CC:-gcc}
omp_args="--nx 512 --ny 512 --steps 100 --ignitions 16"
if make -B CC="$omp_cc" omp >/dev/null 2>&1; then
    serial=$(checksum $omp_args)
    for t in 1 2 4 8; do
        line=$(OMP_NUM_THREADS=$t build/firefront_omp $omp_args | grep '^RESULT')
        threads=$(echo "$line" | sed 's/.* threads=\([0-9]*\).*/\1/')
        omp=$(echo "$line" | sed 's/.*checksum=\(0x[0-9a-f]*\).*/\1/')
        check "OpenMP ($omp_cc) runs with $t thread(s)" "$t" "$threads"
        check "OpenMP with $t thread(s) gives the serial checksum" "$serial" "$omp"
    done
else
    echo "skipped: OpenMP checksum test ($omp_cc cannot build with -fopenmp; set OMP_CC, e.g. OMP_CC=gcc-16)"
fi

exit $fail
