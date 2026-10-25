#!/bin/bash
# E2 (OpenMP part): thread scaling, same problem as E1 (8192 x 8192, 400 steps, 16 ignitions).
# One repetition per job. Each job runs the whole thread series, one run after another,
# and every run prints its own RESULT line:
#   1, 2, 4, 8, 16, 32 threads, one per physical core (OMP_PLACES=cores, OMP_PROC_BIND=close)
#   64 threads, two per core on the hyper-threads of the same 32 cores (OMP_PLACES=threads)
#
# This script builds nothing: run slurm/build.sbatch first.
# Submit from the repository root. Whole series (3 repetitions = 3 jobs):
#   for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e2_omp_threads.sbatch; done
#
# Resources: the student QOS allows 64 CPUs per user, and Slurm counts every hardware
# thread as a CPU (2 per core). --cpus-per-task=64 with --hint=multithread therefore gives
# 32 whole cores with both of their hardware threads, exactly the limit, which the 64-thread
# run needs. (--cpus-per-task=64 with --hint=nomultithread would mean 64 cores, i.e. 128 CPUs,
# and stay pending over the limit.) The log prints NumCPUs and the usable CPU list to check this.
#
# Time: on a laptop the serial E1 problem takes 55 s. Assuming a cluster core is up to 2x
# slower, 1 thread takes about 2 min and the whole series (1 + 1/2 + 1/4 + ... plus losses)
# about 2.1 times that, around 4-5 min. Even if another job shares our cores and doubles
# that, it stays under 10 min. RESULT lines of finished runs stay in the log even if the
# job is stopped at the time limit.
#
# Same job name as E1, STREAM and the build: with --dependency=singleton only one of them
# runs at a time. Other users' jobs can still share the node, so the log records them.
# Pinned to haskell (--nodelist): the -march=native build and every timed run then use
# the same CPU, and env/cluster.md describes that node (cluster_info was taken there).
# --sockets-per-node=1: 32 cores fit in one 128-core socket, so the run stays in one
# NUMA domain (local memory only). Remove that line if jobs stay pending.
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/e2_omp_threads_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64
#SBATCH --hint=multithread
#SBATCH --mem=2G
#SBATCH --time=00:10:00
#SBATCH --dependency=singleton
#SBATCH --nodelist=haskell
#SBATCH --sockets-per-node=1

NX=${NX:-8192}
STEPS=${STEPS:-400}
REP=${REP:-1}

source slurm/job_helpers.sh

module purge
module load GCC/13.2.0 || exit 1   # see env/modules.txt

bin=./build/firefront_omp
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run slurm/build.sbatch first"
    exit 1
fi

cpus=${SLURM_CPUS_PER_TASK:-64}    # hardware threads of this job
cores=$((cpus / 2))                # 2 hardware threads per core

echo "rep=$REP"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

# print where each thread runs, to check the pinning
export OMP_DISPLAY_AFFINITY=true
export OMP_AFFINITY_FORMAT="thread %n of %N on cpus %A"
export OMP_PROC_BIND=close
args=(--nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42 --ignitions 16)

for ((t = 1; t <= cores; t *= 2)); do
    echo "== run: $t thread(s), one per physical core =="
    export OMP_NUM_THREADS=$t OMP_PLACES=cores
    run_logged "$bin" "${args[@]}"
done

echo "== run: $cpus threads on the hyper-threads of the $cores cores =="
export OMP_NUM_THREADS=$cpus OMP_PLACES=threads
run_logged "$bin" "${args[@]}"

node_state end
