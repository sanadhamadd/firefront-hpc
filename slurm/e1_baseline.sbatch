#!/bin/bash
# E1 baseline: serial version, L grid (8192 x 8192), 400 steps, 16 ignitions. One repetition per job.
#
# This script builds nothing: run slurm/build.sbatch first.
# Submit from the repository root. Whole series (3 repetitions):
#   for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e1_baseline.sbatch; done
#
# One core only: we ask for what the run needs, not the whole node.
# Same job name as E2, STREAM and the build: with --dependency=singleton only one of them
# runs at a time, so our own jobs never share cores or memory bandwidth with each other.
# Pinned to haskell (--nodelist): the -march=native build and every timed run then use
# the same CPU, and env/cluster.md describes that node (cluster_info was taken there).
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/e1_baseline_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:10:00
#SBATCH --dependency=singleton
#SBATCH --nodelist=haskell

NX=${NX:-8192}
STEPS=${STEPS:-400}
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

run_logged "$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42 --ignitions 16

node_state end
