#!/bin/bash
# OpenACC checksum against serial. Skips when nvc is missing or the host
# compiler cannot build the znver4 objects the GPU Makefile uses.
# Multicore does not need a GPU. The GPU binary is checked only when nvidia-smi works.

set -u

if ! command -v nvc >/dev/null 2>&1; then
    echo "skipped: OpenACC checksum test (nvc not found)"
    exit 0
fi
cc=${CC:-gcc}
if ! echo 'int main(void){return 0;}' | "$cc" -march=znver4 -x c - -c -o /dev/null 2>/dev/null; then
    echo "skipped: OpenACC checksum test ($cc has no -march=znver4)"
    exit 0
fi

fail=0
check() {
    if [ "$2" = "$3" ]; then
        echo "ok:   acc $1"
    else
        echo "FAIL: acc $1 ($2 vs $3)"
        fail=1
    fi
}
serial_verify() {
    ./build/firefront_serial "$@" --verify-only | grep '^VERIFY '
}

run_one() {
    local target=$1 bin=$2
    if ! make "$target" >/dev/null; then
        echo "FAIL: make $target"
        fail=1
        return
    fi
    local args="--nx 96 --ny 80 --steps 25 --seed 4 --ignitions 3"
    # shellcheck disable=SC2086
    check "$target $args" "$(serial_verify $args)" "$("./$bin" $args --verify-only | grep '^VERIFY ')"
    if [ "${CUDA_CHECK_E1:-0}" = 1 ]; then
        check "$target E1" "VERIFY checksum=0xb8683c550fa95bd6" \
            "$("./$bin" --nx 8192 --ny 8192 --steps 400 --seed 42 --ignitions 16 --verify-only | grep '^VERIFY ')"
    fi
}

run_one acc-mc build/firefront_acc_mc

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    run_one acc build/firefront_acc
else
    echo "skipped: OpenACC GPU binary (no GPU); multicore was still checked"
fi

exit $fail
