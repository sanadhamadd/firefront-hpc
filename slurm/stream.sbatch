#!/bin/bash
# STREAM triad: memory bandwidth for the roofline (tools/roofline.py).
# One repetition per job. Each job runs the same thread series as E2, one run after another,
# and every run prints its own RESULT line:
#   1, 2, 4, 8, 16, 32 threads, one per physical core (OMP_PLACES=cores, OMP_PROC_BIND=close)
#   64 threads, two per core on the hyper-threads of the same 32 cores (OMP_PLACES=threads)
#
# What it measures: the student QOS allows at most 64 CPUs = 32 cores per user, so this
# is the bandwidth available to 32 cores, not to the whole 256-core node. That is the right
# number for our roofline, because E2 runs on the same 32 cores.
#
# Array size: STREAM's rule is that each array must be at least 4 times the last-level
# cache, so the triad really runs from memory. A node has 1 GiB of L3 in total, so each of
# the 3 arrays should hold about 4 x 1 GiB = 4.3 GB: DOUBLES=1.6e9 gives 3 x 533 million
# doubles, 4.27 GB each, 12.8 GB in all (a hair under 4 x, which does not matter: our 32
# cores only reach about 128 MB of that L3, so the arrays are over 30 times their cache).
# The program's own default (4e8) is unchanged.
#
# This script builds nothing: run slurm/build.sbatch first.
# Submit from the repository root. Whole series (3 repetitions = 3 jobs):
#   for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/stream.sbatch; done
#
# Resources as in E2: --cpus-per-task=64 with --hint=multithread = 32 whole cores with both
# hardware threads, the 64-CPU limit. Same job name as E1, E2 and the build: with
# --dependency=singleton only one of them runs at a time.
# Pinned to haskell (--nodelist): the -march=native build and every timed run then use
# the same CPU, and env/cluster.md describes that node (cluster_info was taken there).
# --sockets-per-node=1: 32 cores fit in one 128-core socket, so the run stays in one
# NUMA domain (local memory only). Remove that line if jobs stay pending.
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/stream_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64
#SBATCH --hint=multithread
#SBATCH --mem=16G
#SBATCH --time=00:10:00
#SBATCH --dependency=singleton
#SBATCH --nodelist=haskell
#SBATCH --sockets-per-node=1

DOUBLES=${DOUBLES:-1.6e9}
REP=${REP:-1}

source slurm/job_helpers.sh

module purge
module load GCC/13.2.0 || exit 1   # see env/modules.txt

bin=./build/stream
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

export OMP_DISPLAY_AFFINITY=true
export OMP_AFFINITY_FORMAT="thread %n of %N on cpus %A"
export OMP_PROC_BIND=close

for ((t = 1; t <= cores; t *= 2)); do
    echo "== run: $t thread(s), one per physical core =="
    export OMP_NUM_THREADS=$t OMP_PLACES=cores
    run_logged "$bin" --doubles "$DOUBLES"
done

echo "== run: $cpus threads on the hyper-threads of the $cores cores =="
export OMP_NUM_THREADS=$cpus OMP_PLACES=threads
run_logged "$bin" --doubles "$DOUBLES"

node_state end
