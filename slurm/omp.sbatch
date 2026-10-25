#!/bin/bash
# OpenMP on one node, one repetition per job. Threads come from --cpus-per-task.
# General template; the E2 thread series is slurm/e2_omp_threads.sbatch.
#
# This script builds nothing: run slurm/build.sbatch first.
# With --hint=nomultithread, --cpus-per-task=t should give t whole cores (2t CPUs counted
# against the student limit of 64 CPUs per user), so t can be at most 32. The log prints
# NumCPUs to check.
# Submit from the repository root, e.g. threads 1 to 32, 3 repetitions each (at most 8 jobs
# may be queued per user, so send these in parts):
#   for t in 1 2 4 8 16 32; do for rep in 1 2 3; do sbatch --cpus-per-task=$t --export=ALL,NX=8192,REP=$rep slurm/omp.sbatch; done; done
#SBATCH --job-name=ff-omp
#SBATCH --output=results/raw/omp_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=2G
#SBATCH --time=00:10:00
#SBATCH --hint=nomultithread
#SBATCH --partition=cpu

NX=${NX:-8192}
STEPS=${STEPS:-500}
REP=${REP:-1}

source slurm/job_helpers.sh

module purge
module load GCC/13.2.0 || exit 1   # see env/modules.txt

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=close
export OMP_PLACES=cores

bin=./build/firefront_omp
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run slurm/build.sbatch first"
    exit 1
fi

echo "rep=$REP"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

echo "OMP_NUM_THREADS=$OMP_NUM_THREADS"
run_logged "$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42

node_state end
