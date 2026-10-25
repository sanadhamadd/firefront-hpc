#!/bin/bash
# Single GPU run, one repetition per job. Keep it short, the GPUs are shared.
# Not usable yet: build/firefront_cuda does not exist (phase 3c).
#
# This script builds nothing: build the CUDA version with a job like slurm/build.sbatch, once it exists.
# Submit from the repository root, e.g. 3 repetitions:
#   for rep in 1 2 3; do sbatch --export=ALL,NX=8192,REP=$rep slurm/gpu.sbatch; done
#SBATCH --job-name=ff-gpu
#SBATCH --output=results/raw/gpu_%j.out
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:10:00
# The two nodes have different GPUs (rtx6000ada on one, rtx6000bb on the other, see env/cluster.md).
# To compare runs, always ask for the same type, e.g. --gres=gpu:rtx6000ada:1.

NX=${NX:-8192}
STEPS=${STEPS:-500}
REP=${REP:-1}

source slurm/job_helpers.sh

module purge
module load hpc-course-cuda/12.8.1   # for the OpenACC version: nvhpc/25.7, see env/modules.txt

bin=./build/firefront_cuda
if [ ! -x "$bin" ]; then
    echo "$bin is missing: build the CUDA version first"
    exit 1
fi

echo "rep=$REP"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

cmd=("$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42)
echo "command: ${cmd[*]}"
"${cmd[@]}"

node_state end
