#!/bin/bash
# Build both OpenACC binaries and check them against the serial checksums.
# Run this only after the CUDA checksum has passed: OpenACC is the comparison,
# not a second experiment to debug at the same time.
#
#   sbatch slurm/acc_build.sbatch
# The log should end with "acc checksums ok". If nvc cannot link the gcc objects
# or the checksum differs, say so in the report and keep the CUDA numbers.
# Multicore (-acc=multicore) is the fallback when the GPU queue never starts.
#SBATCH --job-name=ff-acc-build
#SBATCH --output=results/raw/acc_build_%j.out
#SBATCH --partition=gpu
#SBATCH --gres=gpu:rtx6000ada:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:30:00

source slurm/job_helpers.sh

module purge
module load GCC/13.2.0 || exit 1
GCC_BIN=$(command -v gcc)
module load nvhpc/25.7 || exit 1
# nvhpc sets CC=nvc and puts the system gcc first. Host objects must stay on GCC 13.2.
export CC=$GCC_BIN
export PATH="$(dirname "$GCC_BIN"):$PATH"
echo "gcc: $(command -v gcc) $(gcc -dumpversion) CC=$CC"
echo "nvc: $(command -v nvc)"
nvc --version | head -n 2

node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

if [ ! -x build/firefront_serial ]; then
    NATIVE=-march=znver4 make serial || exit 1
fi
export CUDA_CHECK_E1=1
if ! bash tests/run_acc.sh; then
    echo "ACC CHECK FAILED: removing the OpenACC binaries"
    rm -f build/firefront_acc build/firefront_acc_mc
    node_state end
    exit 1
fi
echo "acc checksums ok"
node_state end
exit 0
