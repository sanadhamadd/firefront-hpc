#!/bin/bash
# E5 (and the MPI part of E2): pure MPI, one rank per core, one thread per rank.
# Same problem as E1/E2: 8192 x 8192, 400 steps, 16 ignitions, seed 42.
# One configuration and one repetition per job; the ranks, nodes and decomposition come
# from the sbatch command line and DECOMP. Use slurm/submit_e5.sh to submit the series.
#
# Single job by hand, e.g. 16 ranks as blocks on one node:
#   sbatch --nodes=1 --ntasks-per-node=16 --nodelist=haskell --export=ALL,DECOMP=blocks,REP=1 slurm/e5_decomp.sbatch
# or 16 ranks on two nodes (8 each):
#   sbatch --nodes=2 --ntasks-per-node=8 --nodelist=haskell,julia --export=ALL,DECOMP=blocks,REP=1 slurm/e5_decomp.sbatch
#
# Limits: 64 CPUs per user = 32 cores (--hint=nomultithread makes every task a whole core,
# which Slurm counts as 2 CPUs), so at most 32 ranks in total, also over two nodes.
# LAUNCH is how MPI is started; slurm/mpi_check.sbatch tells which launcher works.
# Same job name and singleton dependency as the other timed jobs: one at a time.
# The log says "checksum ok" if the run reproduces the serial result of E1.
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/e5_decomp_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --dependency=singleton
#SBATCH --nodelist=haskell

NX=${NX:-8192}
STEPS=${STEPS:-400}
DECOMP=${DECOMP:-blocks}
REP=${REP:-1}
LAUNCH=${LAUNCH:-srun --cpu-bind=cores}
# serial checksum of the E1 problem (docs/handover.md); only checked for that problem
REFERENCE=0xb8683c550fa95bd6

source slurm/job_helpers.sh

module purge
module load OpenMPI/4.1.6-GCC-13.2.0 || exit 1   # also loads GCC/13.2.0, see env/modules.txt
echo "mpicc: $(command -v mpicc)  mpirun: $(command -v mpirun)"
mpirun --version 2>&1 | head -n 1

bin=./build/firefront_mpi
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run slurm/build.sbatch first"
    exit 1
fi

echo "rep=$REP decomp=$DECOMP ranks=$SLURM_NTASKS nodes=$SLURM_JOB_NUM_NODES nodelist=$SLURM_JOB_NODELIST"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

export OMP_NUM_THREADS=1
# run directly, not with run_logged: numastat of srun or mpirun would describe the
# launcher, not the MPI ranks
echo "command: $LAUNCH $bin ..."
out=$($LAUNCH "$bin" --nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42 --ignitions 16 \
      --decomp "$DECOMP" --overlap 0)
status=$?
echo "$out"

if [ "$NX" = 8192 ] && [ "$STEPS" = 400 ]; then
    got=$(echo "$out" | grep '^RESULT' | sed 's/.*checksum=\(0x[0-9a-f]*\).*/\1/')
    if [ "$got" = "$REFERENCE" ]; then echo "checksum ok"; else echo "CHECKSUM MISMATCH: $got, serial $REFERENCE"; fi
fi

node_state end
exit $status
