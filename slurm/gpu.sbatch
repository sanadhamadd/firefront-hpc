#!/bin/bash
# Single GPU run, one repetition per job. Keep it short, the GPUs are shared.
# Not usable yet: build/firefront_cuda does not exist (phase 3c).
#
# This script builds nothing: build the CUDA version on the login node first, once it exists.
# Submit from the repository root, e.g. 3 repetitions:
#   for rep in 1 2 3; do sbatch --export=ALL,NX=8192,REP=$rep slurm/gpu.sbatch; done
#SBATCH --job-name=ff-gpu
#SBATCH --output=results/raw/gpu_%j.out
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:10:00
# TODO: check the name of the GPU partition in the cluster info

NX=${NX:-8192}
STEPS=${STEPS:-500}
REP=${REP:-1}

# TODO: module purge; module load <CUDA or NVHPC module>   (see env/modules.txt once filled in)

bin=./build/firefront_cuda
if [ ! -x "$bin" ]; then
    echo "$bin is missing: build the CUDA version on the login node first"
    exit 1
fi

echo "rep=$REP"
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

cmd=("$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42)
echo "command: ${cmd[*]}"
"${cmd[@]}"
