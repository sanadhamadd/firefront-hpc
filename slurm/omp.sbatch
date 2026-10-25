#!/bin/bash
# OpenMP on one node, one repetition per job. Threads come from --cpus-per-task.
# General template; the E2 thread series is slurm/e2_omp_threads.sbatch.
#
# This script builds nothing: run "make omp" on the login node first (with the GCC module loaded).
# Submit from the repository root, e.g. threads 1 to 32, 3 repetitions each:
#   for t in 1 2 4 8 16 32; do for rep in 1 2 3; do sbatch --cpus-per-task=$t --export=ALL,NX=8192,REP=$rep slurm/omp.sbatch; done; done
#SBATCH --job-name=ff-omp
#SBATCH --output=results/raw/omp_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --hint=nomultithread

NX=${NX:-8192}
STEPS=${STEPS:-500}
REP=${REP:-1}

# TODO: module purge; module load <GCC module>   (see env/modules.txt once filled in)

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=close
export OMP_PLACES=cores

bin=./build/firefront_omp
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run make omp on the login node first"
    exit 1
fi

echo "rep=$REP"
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

cmd=("$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42)
echo "command: OMP_NUM_THREADS=$OMP_NUM_THREADS ${cmd[*]}"
"${cmd[@]}"
