#!/bin/bash
# E1 baseline: serial version, L grid (8192 x 8192), 400 steps, 16 ignitions. One repetition per job.
#
# This script builds nothing: run "make" on the login node first.
# Submit from the repository root. Whole series (3 repetitions):
#   for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e1_baseline.sbatch; done
#
# One core only: we ask for what the run needs, not the whole node.
#SBATCH --job-name=ff-e1
#SBATCH --output=results/raw/e1_baseline_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --partition=cpu
#SBATCH --account=hpcclass
#SBATCH --qos=student

NX=${NX:-8192}
STEPS=${STEPS:-400}
REP=${REP:-1}

module purge
module load GCC/13.2.0   # see env/modules.txt

bin=./build/firefront_serial
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run make on the login node first"
    exit 1
fi

echo "rep=$REP"
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

cmd=("$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42 --ignitions 16)
echo "command: ${cmd[*]}"
"${cmd[@]}"
