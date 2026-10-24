#!/bin/bash
# Serial baseline. One core, one rank.
# Example: sbatch --export=ALL,NX=4096,STEPS=1000 slurm/serial.sbatch
#SBATCH --job-name=ff-serial
#SBATCH --output=results/raw/serial_%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:15:00

NX=${NX:-4096}
STEPS=${STEPS:-1000}

bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

for rep in 1 2 3 4 5; do
    ./build/firefront_serial --nx $NX --ny $NX --steps $STEPS --seed 42
done
