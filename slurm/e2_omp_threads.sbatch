#!/bin/bash
# E2 (OpenMP part): thread scaling on one node, same problem as E1
# (8192 x 8192, 400 steps, 16 ignitions). One repetition per job; threads come from --cpus-per-task.
#
# This script builds nothing: run "make omp" on the login node first (with the GCC module loaded).
# A node has 2 sockets x 128 cores x 2 hardware threads (env/cluster.md). The series uses
# powers of two up to the 256 physical cores, one thread per core (--hint=nomultithread),
# plus one run with 512 threads on all hardware threads (--hint=multithread on the command
# line overrides the line below; the script then places one thread per hardware thread).
# Submit from the repository root. Whole series (10 thread counts x 3 repetitions = 30 jobs):
#   for rep in 1 2 3; do
#     for t in 1 2 4 8 16 32 64 128 256; do sbatch --cpus-per-task=$t --export=ALL,REP=$rep slurm/e2_omp_threads.sbatch; done
#     sbatch --cpus-per-task=512 --hint=multithread --export=ALL,REP=$rep slurm/e2_omp_threads.sbatch
#   done
#
# Why the whole node (--exclusive): the update loop moves a lot of memory per cell,
# so with many threads it is limited by the node's memory bandwidth. Another job on
# the same node would use part of that bandwidth and make our times slower and
# noisier, and the thread-scaling curve would show the other job, not our code.
# Remove the line only if the cluster does not allow it.
#SBATCH --job-name=ff-e2
#SBATCH --output=results/raw/e2_omp_threads_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --exclusive
#SBATCH --hint=nomultithread
#SBATCH --partition=cpu
#SBATCH --account=hpcclass
#SBATCH --qos=student

NX=${NX:-8192}
STEPS=${STEPS:-400}
REP=${REP:-1}

module purge
module load GCC/13.2.0   # see env/modules.txt

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=close
export OMP_PLACES=cores
# more threads than the 256 physical cores (the 512 run): one thread per hardware thread
if [ "$OMP_NUM_THREADS" -gt 256 ]; then export OMP_PLACES=threads; fi

bin=./build/firefront_omp
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run make omp on the login node first"
    exit 1
fi

echo "rep=$REP"
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

cmd=("$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42 --ignitions 16)
echo "command: OMP_NUM_THREADS=$OMP_NUM_THREADS ${cmd[*]}"
"${cmd[@]}"
