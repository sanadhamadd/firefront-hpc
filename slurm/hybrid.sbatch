#!/bin/bash
# MPI + OpenMP, one repetition per job. Ranks x threads = cores used.
# Not usable yet: build/firefront_mpi and its --decomp / --overlap options do not exist (phase 2).
#
# This script builds nothing: run the MPI make target on the login node first, once it exists.
# Submit from the repository root, e.g. 2 nodes, 8 ranks per node, 4 threads each = 64 cores, 3 repetitions:
#   for rep in 1 2 3; do sbatch --nodes=2 --ntasks-per-node=8 --cpus-per-task=4 --export=ALL,NX=8192,DECOMP=blocks,OVERLAP=1,REP=$rep slurm/hybrid.sbatch; done
#SBATCH --job-name=ff-hybrid
#SBATCH --output=results/raw/hybrid_%j.out
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:10:00
#SBATCH --hint=nomultithread
#SBATCH --partition=cpu
#SBATCH --account=hpcclass
#SBATCH --qos=student

NX=${NX:-8192}
STEPS=${STEPS:-500}
DECOMP=${DECOMP:-blocks}
OVERLAP=${OVERLAP:-1}
REP=${REP:-1}

module purge
module load OpenMPI/4.1.6-GCC-13.2.0   # also loads GCC/13.2.0, see env/modules.txt

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=close
export OMP_PLACES=cores

bin=./build/firefront_mpi
if [ ! -x "$bin" ]; then
    echo "$bin is missing: build the MPI version on the login node first"
    exit 1
fi

echo "rep=$REP"
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

cmd=(srun --cpu-bind=cores "$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42
     --decomp "$DECOMP" --overlap "$OVERLAP")
echo "command: ${cmd[*]}"
"${cmd[@]}"
