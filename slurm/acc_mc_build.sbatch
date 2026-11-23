#!/bin/bash
# Build the OpenACC multicore binary on haskell and check the E1 checksum.
# This is the path that does not need a GPU. Use it when the gpu partition
# does not start. It does not build the CUDA or OpenACC GPU binaries.
#
#   sbatch slurm/acc_mc_build.sbatch
# Then, if the log ends with "acc multicore checksums ok":
#   for rep in 1 2 3; do sbatch slurm/acc_mc.sbatch; done
#SBATCH --job-name=ff-acc-mc-build
#SBATCH --output=results/raw/acc_mc_build_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=8G
#SBATCH --time=00:20:00
#SBATCH --nodelist=haskell

REFERENCE=0xb8683c550fa95bd6

source slurm/job_helpers.sh

module purge
module load GCC/13.2.0 || exit 1
module load nvhpc/25.7 || exit 1
echo "gcc: $(command -v gcc) $(gcc -dumpversion)"
echo "nvc: $(command -v nvc)"

node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

NATIVE=-march=znver4 make serial || exit 1
make acc-mc || exit 1

fail=0
check() {
    got=$(./build/firefront_acc_mc "$@" --verify-only | grep '^VERIFY ')
    want=$(./build/firefront_serial "$@" --verify-only | grep '^VERIFY ')
    if [ "$got" = "$want" ]; then
        echo "ok: acc-mc $*"
    else
        echo "FAIL: acc-mc $* ($got vs $want)"
        fail=1
    fi
}
check --nx 96 --ny 80 --steps 25 --seed 4 --ignitions 3
e1=$(./build/firefront_acc_mc --nx 8192 --ny 8192 --steps 400 --seed 42 --ignitions 16 --verify-only | grep '^VERIFY ')
if [ "$e1" = "VERIFY checksum=$REFERENCE" ]; then
    echo "ok: acc-mc E1"
else
    echo "FAIL: acc-mc E1 ($e1)"
    fail=1
fi
if [ $fail -ne 0 ]; then
    rm -f build/firefront_acc_mc
    node_state end
    exit 1
fi
echo "acc multicore checksums ok"
node_state end
exit 0
