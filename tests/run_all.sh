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
for field in variant nx ny steps seed threads t_total cells_per_s burning burnt checksum commit; do
    case "$line" in
        *" $field="*) ;;
        *) echo "FAIL: RESULT line has no $field"; fail=1 ;;
    esac
done
echo "ok:   RESULT line has all fields"

if "$bin" --nx 2 >/dev/null 2>&1; then echo "FAIL: tiny grid was accepted"; fail=1; else echo "ok:   tiny grid is rejected"; fi

exit $fail
