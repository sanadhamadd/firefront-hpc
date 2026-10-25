#!/bin/bash
# MPI + OpenMP, one repetition per job. Ranks x threads = cores used.
# Not usable yet: build/firefront_mpi and its --decomp / --overlap options do not exist (phase 2).
#
# This script builds nothing: build the MPI version with a job like slurm/build.sbatch, once it exists.
# Limit: the student QOS allows 64 CPUs per user in total, i.e. 32 cores (2 hardware threads
# each), e.g. 2 nodes x 16 cores. With --hint=nomultithread each CPU of --cpus-per-task is a
# whole core, so the default below is 2 nodes x 4 ranks x 4 cores = 32 cores.
# Submit from the repository root, e.g. 3 repetitions:
#   for rep in 1 2 3; do sbatch --nodes=2 --ntasks-per-node=4 --cpus-per-task=4 --export=ALL,NX=8192,DECOMP=blocks,OVERLAP=1,REP=$rep slurm/hybrid.sbatch; done
#SBATCH --job-name=ff-hybrid
#SBATCH --output=results/raw/hybrid_%j.out
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=4
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --hint=nomultithread
#SBATCH --partition=cpu

NX=${NX:-8192}
STEPS=${STEPS:-500}
DECOMP=${DECOMP:-blocks}
OVERLAP=${OVERLAP:-1}
REP=${REP:-1}

source slurm/job_helpers.sh

module purge
# The node also has a system mpirun (Open MPI 5.0.7). Build and run must use this module's MPI,
# so load it before srun and check in the log that mpicc/mpirun come from it (env/cluster.md).
module load OpenMPI/4.1.6-GCC-13.2.0 || exit 1   # also loads GCC/13.2.0, see env/modules.txt
echo "mpicc: $(command -v mpicc)  mpirun: $(command -v mpirun)"
mpirun --version 2>&1 | head -n 1

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=close
export OMP_PLACES=cores

bin=./build/firefront_mpi
if [ ! -x "$bin" ]; then
    echo "$bin is missing: build the MPI version first"
    exit 1
fi

echo "rep=$REP"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

cmd=(srun --cpu-bind=cores "$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42
     --decomp "$DECOMP" --overlap "$OVERLAP")
echo "command: ${cmd[*]}"
"${cmd[@]}"

node_state end
