#!/bin/bash
# MPI + OpenMP. Ranks x threads = cores used.
# Example (2 nodes, 8 ranks per node, 4 threads each = 64 cores):
#   sbatch --nodes=2 --ntasks-per-node=8 --cpus-per-task=4 \
#          --export=ALL,NX=8192,DECOMP=blocks,OVERLAP=1 slurm/hybrid.sbatch
#SBATCH --job-name=ff-hybrid
#SBATCH --output=results/raw/hybrid_%j.out
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:15:00
#SBATCH --hint=nomultithread

NX=${NX:-8192}
STEPS=${STEPS:-500}
DECOMP=${DECOMP:-blocks}
OVERLAP=${OVERLAP:-1}

module purge
module load OpenMPI/4.1.5-GCC-12.3.0    # check env/modules.txt for what the cluster really has

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=close
export OMP_PLACES=cores

bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

for rep in 1 2 3 4 5; do
    srun --cpu-bind=cores ./build/firefront_mpi --nx $NX --ny $NX --steps $STEPS \
         --seed 42 --decomp $DECOMP --overlap $OVERLAP
done
