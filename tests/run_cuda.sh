#!/bin/bash
# Compare the CUDA binary with the serial one. Skips when nvcc, a GPU, or
# -march=znver4 is missing, so "make test" still passes on a laptop.
# The E1 grid (8192^2, 400 steps) runs only when CUDA_CHECK_E1=1 (the GPU build job).

set -u

if command -v cuda-exec >/dev/null 2>&1; then
    export NVCC="cuda-exec nvcc"
    export NVCC_CCBIN=
    cuda_run=(cuda-exec ./build/firefront_cuda)
elif ! command -v nvcc >/dev/null 2>&1; then
    echo "skipped: CUDA checksum test (nvcc not found)"
    exit 0
else
    cuda_run=(./build/firefront_cuda)
fi
if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
    echo "skipped: CUDA checksum test (no GPU)"
    exit 0
fi
cc=${CC:-gcc}
if ! echo 'int main(void){return 0;}' | "$cc" -march=znver4 -x c - -c -o /dev/null 2>/dev/null; then
    echo "skipped: CUDA checksum test ($cc has no -march=znver4; the GPU binary is built on the cluster)"
    exit 0
fi

arch=${CUDA_ARCH:-native}
if ! make cuda CUDA_ARCH="$arch" >/dev/null; then
    echo "FAIL: make cuda CUDA_ARCH=$arch"
    exit 1
fi

fail=0
check() {
    if [ "$2" = "$3" ]; then
        echo "ok:   cuda $1"
    else
        echo "FAIL: cuda $1 ($2 vs $3)"
        fail=1
    fi
}

serial_verify() {
    ./build/firefront_serial "$@" --verify-only | grep '^VERIFY '
}
cuda_verify() {
    "${cuda_run[@]}" "$@" --verify-only | grep '^VERIFY '
}

for args in \
    "--nx 1024 --ny 1024 --steps 100" \
    "--nx 200 --ny 150 --steps 40 --seed 7 --ignitions 5" \
    "--nx 64 --ny 48 --steps 30 --humidity 0.4 --ignitions 3 --seed 9"
do
    # shellcheck disable=SC2086
    check "$args" "$(serial_verify $args)" "$(cuda_verify $args)"
done

check "default 1024 x 1024, 100 steps keeps its reference checksum" \
    "VERIFY checksum=0x74cfadfb78e73134" "$(cuda_verify --nx 1024 --ny 1024 --steps 100)"

if [ "${CUDA_CHECK_E1:-0}" = 1 ]; then
    check "E1 8192 x 8192, 400 steps, 16 ignitions" \
        "VERIFY checksum=0xb8683c550fa95bd6" \
        "$(cuda_verify --nx 8192 --ny 8192 --steps 400 --seed 42 --ignitions 16)"
fi

line=$("${cuda_run[@]}" --nx 64 --ny 64 --steps 5 --seed 1)
result=$(printf '%s\n' "$line" | grep '^RESULT')
case "$result" in
    *"variant=cuda"*"t_kernel="*"t_with_copies="*) echo "ok:   cuda RESULT line has t_kernel and t_with_copies" ;;
    *) echo "FAIL: cuda RESULT line is missing the device timers"; echo "$result"; fail=1 ;;
esac

err=$(mktemp)
if "${cuda_run[@]}" --nx 32 --ny 32 --steps 1 --skip-tiles 4 >/dev/null 2>"$err"; then
    echo "FAIL: cuda accepted --skip-tiles"
    fail=1
elif grep -q "CPU-only" "$err"; then
    echo "ok:   cuda rejects --skip-tiles"
else
    echo "FAIL: cuda --skip-tiles was rejected without the CPU-only message"
    cat "$err"
    fail=1
fi
rm -f "$err"

exit $fail
