#!/bin/bash
# Serial run, one core, one repetition per job. General template; E1 is slurm/e1_baseline.sbatch.
#
# This script builds nothing: run slurm/build.sbatch first.
# Submit from the repository root, e.g. 3 repetitions:
#   for rep in 1 2 3; do sbatch --export=ALL,NX=4096,STEPS=1000,REP=$rep slurm/serial.sbatch; done
#SBATCH --job-name=ff-serial
#SBATCH --output=results/raw/serial_%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:10:00
#SBATCH --partition=cpu

NX=${NX:-4096}
STEPS=${STEPS:-1000}
REP=${REP:-1}

source slurm/job_helpers.sh

module purge
module load GCC/13.2.0 || exit 1   # see env/modules.txt

bin=./build/firefront_serial
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run slurm/build.sbatch first"
    exit 1
fi

echo "rep=$REP"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

run_logged "$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42

node_state end
