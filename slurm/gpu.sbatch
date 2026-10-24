#!/bin/bash
# Single GPU run. Keep it short, the GPUs are shared.
#SBATCH --job-name=ff-gpu
#SBATCH --output=results/raw/gpu_%j.out
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:10:00

NX=${NX:-8192}
STEPS=${STEPS:-500}

# load the CUDA module here once we know its name (see env/modules.txt)

bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

for rep in 1 2 3 4 5; do
    ./build/firefront_cuda --nx $NX --ny $NX --steps $STEPS --seed 42
done
