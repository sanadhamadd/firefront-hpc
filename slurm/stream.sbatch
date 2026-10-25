#!/bin/bash
# STREAM triad on a whole node: memory bandwidth for the roofline (tools/roofline.py).
# One repetition per job; threads come from --cpus-per-task (default 32 = a full node,
# assuming 2 sockets x 16 cores, TODO: check against the cluster info).
#
# This script builds nothing: run "make stream" on the login node first (with the GCC module loaded).
# Submit from the repository root. Whole series (6 thread counts x 3 repetitions = 18 jobs):
#   for t in 1 2 4 8 16 32; do for rep in 1 2 3; do sbatch --cpus-per-task=$t --export=ALL,REP=$rep slurm/stream.sbatch; done; done
#
# Why the whole node (--exclusive): STREAM measures the node's memory bandwidth,
# which all jobs on the node share. Another job running next to it would lower the
# number, and the roofline bound built from it would be wrong. Remove the line only
# if the cluster does not allow it.
# OMP_PROC_BIND=close as in E2, so 16 threads fill one socket first.
#SBATCH --job-name=ff-stream
#SBATCH --output=results/raw/stream_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --exclusive
#SBATCH --hint=nomultithread
# TODO: #SBATCH --partition=<CPU partition>, once we have the cluster info

DOUBLES=${DOUBLES:-4e8}
REP=${REP:-1}

# TODO: module purge; module load <GCC module>   (see env/modules.txt once filled in)

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=close
export OMP_PLACES=cores

bin=./build/stream
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run make stream on the login node first"
    exit 1
fi

echo "rep=$REP"
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

cmd=("$bin" --doubles "$DOUBLES")
echo "command: OMP_NUM_THREADS=$OMP_NUM_THREADS ${cmd[*]}"
"${cmd[@]}"
