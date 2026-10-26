#!/bin/bash
# MPI + OpenMP (E3 hybrid split), one repetition per job. Ranks x threads = cores used.
# Same problem as E1/E2: 8192 x 8192, 400 steps, 16 ignitions, seed 42.
#
# This script builds nothing: run slurm/build.sbatch first (it builds build/firefront_mpi),
# and slurm/mpi_check.sbatch once to find a working LAUNCH.
# --overlap 1 does not exist yet (phase 3); OVERLAP stays 0 until then.
# Limit: the student QOS allows 64 CPUs per user in total, i.e. 32 cores (2 hardware threads
# each), e.g. 2 nodes x 16 cores. With --hint=nomultithread each CPU of --cpus-per-task is a
# whole core, so the default below is 2 nodes x 4 ranks x 4 cores = 32 cores.
# Submit from the repository root, e.g. 3 repetitions:
#   for rep in 1 2 3; do sbatch --nodes=2 --ntasks-per-node=4 --cpus-per-task=4 --export=ALL,DECOMP=blocks,REP=$rep slurm/hybrid.sbatch; done
# One node, 8 ranks x 4 threads:
#   sbatch --nodes=1 --ntasks-per-node=8 --cpus-per-task=4 --nodelist=haskell --export=ALL,DECOMP=strips,REP=1 slurm/hybrid.sbatch
# Same job name and singleton dependency as the other timed jobs: one at a time.
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/hybrid_%j.out
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=4
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --hint=nomultithread
#SBATCH --partition=cpu
#SBATCH --dependency=singleton
#SBATCH --nodelist=haskell,julia

NX=${NX:-8192}
STEPS=${STEPS:-400}
DECOMP=${DECOMP:-blocks}
OVERLAP=${OVERLAP:-0}
REP=${REP:-1}
LAUNCH=${LAUNCH:-srun --cpu-bind=cores}
REFERENCE=0xb8683c550fa95bd6     # serial checksum of the E1 problem

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

echo "decomp=$DECOMP ranks=$SLURM_NTASKS threads=$OMP_NUM_THREADS nodes=$SLURM_JOB_NUM_NODES nodelist=$SLURM_JOB_NODELIST"
# run directly, not with run_logged: numastat of srun or mpirun would describe the
# launcher, not the MPI ranks
echo "command: $LAUNCH $bin ..."
out=$($LAUNCH "$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42 --ignitions 16 \
      --decomp "$DECOMP" --overlap "$OVERLAP")
status=$?
echo "$out"
if [ "$NX" = 8192 ] && [ "$STEPS" = 400 ]; then
    got=$(echo "$out" | grep '^RESULT' | sed 's/.*checksum=\(0x[0-9a-f]*\).*/\1/')
    if [ "$got" = "$REFERENCE" ]; then echo "checksum ok"; else echo "CHECKSUM MISMATCH: $got, serial $REFERENCE"; fi
fi

node_state end
exit $status
