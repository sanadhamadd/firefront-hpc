#!/bin/bash
# Build the CUDA binary on a GPU node and check it against the serial checksums.
#
# The login node has no GPU and its CPU has no AVX, so nvcc must run here.
# Host code is -march=znver4 (Makefile, CUDA_HOST_MARCH): that is what GCC 13.2
# selects for -march=native on haskell, and both cluster CPUs can run it.
# The device is an RTX 6000 Ada, so the architecture is sm_89. Do not use the
# other GPU (rtx6000bb): every timed run asks for the same type.
#
# Submit from the repository root, on the branch that contains this script:
#   sbatch slurm/gpu_build.sbatch
# Wait until the log ends with "cuda checksums ok" before submitting slurm/gpu.sbatch.
# A failed build deletes build/firefront_cuda, so a later timing job stops instead
# of timing a bad binary. This job does not use the cpu jobs' name, so it does
# not queue behind them and does not delete the serial binary.
#SBATCH --job-name=ff-gpu-build
#SBATCH --output=results/raw/gpu_build_%j.out
#SBATCH --partition=gpu
#SBATCH --gres=gpu:rtx6000ada:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:30:00

source slurm/job_helpers.sh

module purge
module load hpc-course-cuda/12.8.1 || exit 1
module load OpenMPI/4.1.6-GCC-13.2.0 || exit 1   # GCC 13.2 after the CUDA module, so nvcc -ccbin gcc is that GCC
echo "gcc: $(command -v gcc) $(gcc -dumpversion)"
echo "nvcc: $(command -v nvcc)"
nvcc --version | tail -n 1
echo "== -march=znver4 on this compiler =="
gcc -march=znver4 -Q --help=target | grep march

node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

export CUDA_ARCH=sm_89
export CUDA_CHECK_E1=1
make clean
NATIVE=-march=znver4 make test
status=$?
if [ $status -ne 0 ]; then
    echo "BUILD OR CUDA CHECK FAILED: removing build/firefront_cuda"
    rm -f build/firefront_cuda
    node_state end
    exit $status
fi

echo "cuda checksums ok"
node_state end
exit 0
