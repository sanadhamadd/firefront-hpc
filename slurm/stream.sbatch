#!/bin/bash
# STREAM triad on a whole node: memory bandwidth for the roofline (tools/roofline.py).
# One repetition per job; threads come from --cpus-per-task (default 256 = all physical
# cores of a node: 2 sockets x 128 cores, see env/cluster.md).
#
# This script builds nothing: run "make stream" on the login node first (with the GCC module loaded).
# Same thread series as E2: powers of two up to the 256 physical cores, plus one run on
# all 512 hardware threads (--hint=multithread on the command line overrides the line below).
# Submit from the repository root. Whole series (10 thread counts x 3 repetitions = 30 jobs):
#   for rep in 1 2 3; do
#     for t in 1 2 4 8 16 32 64 128 256; do sbatch --cpus-per-task=$t --export=ALL,REP=$rep slurm/stream.sbatch; done
#     sbatch --cpus-per-task=512 --hint=multithread --export=ALL,REP=$rep slurm/stream.sbatch
#   done
#
# Why the whole node (--exclusive): STREAM measures the node's memory bandwidth,
# which all jobs on the node share. Another job running next to it would lower the
# number, and the roofline bound built from it would be wrong. Remove the line only
# if the cluster does not allow it.
# OMP_PROC_BIND=close as in E2, so up to 128 threads stay on one socket.
#SBATCH --job-name=ff-stream
#SBATCH --output=results/raw/stream_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=256
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --exclusive
#SBATCH --hint=nomultithread
#SBATCH --partition=cpu
#SBATCH --account=hpcclass
#SBATCH --qos=student

DOUBLES=${DOUBLES:-4e8}
REP=${REP:-1}

module purge
module load GCC/13.2.0   # see env/modules.txt

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=close
export OMP_PLACES=cores
# more threads than the 256 physical cores (the 512 run): one thread per hardware thread
if [ "$OMP_NUM_THREADS" -gt 256 ]; then export OMP_PLACES=threads; fi

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
