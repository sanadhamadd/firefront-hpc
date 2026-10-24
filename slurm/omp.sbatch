#!/bin/bash
# OpenMP on one node. Threads come from --cpus-per-task.
# Example: sbatch --cpus-per-task=16 --export=ALL,NX=8192 slurm/omp.sbatch
#SBATCH --job-name=ff-omp
#SBATCH --output=results/raw/omp_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=8G
#SBATCH --time=00:15:00
#SBATCH --hint=nomultithread

NX=${NX:-8192}
STEPS=${STEPS:-500}

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=close
export OMP_PLACES=cores

bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

for rep in 1 2 3 4 5; do
    ./build/firefront_omp --nx $NX --ny $NX --steps $STEPS --seed 42
done
