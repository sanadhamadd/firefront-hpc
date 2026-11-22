#!/bin/bash
# E8 kernel optimisation, MPI part: does skipping tiles without fire unbalance the ranks?
# Same problem as E1/E5: 8192 x 8192, 400 steps, 16 ignitions, seed 42, blocks, blocking
# halo exchange, one thread per rank. One repetition per job, and in it the same binary
# runs twice in the same allocation: without skipping and with --skip-tiles $TILE (odd
# repetitions without first, even ones with first). Both must print the E1 checksum.
# Look at t_total, t_halo, t_compute and imbalance (slowest rank's compute / average).
#
# This script builds nothing: run slurm/build.sbatch first. Submit all configurations
# with slurm/submit_e8.sh, or one by hand, e.g. 32 ranks on one node:
#   sbatch --nodes=1 --ntasks=32 --ntasks-per-node=32 --nodelist=haskell --export=ALL,REP=1 slurm/e8_skip_tiles_mpi.sbatch
# The log name is e8_mpi_*.out on purpose: tools/phase3a_results.py reads hybrid_*.out
# (E3/E4) and tools/plot_e5.py reads e5_decomp_*.out, so these runs stay out of them.
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/e8_mpi_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=32
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --dependency=singleton
#SBATCH --nodelist=haskell

NX=${NX:-8192}
STEPS=${STEPS:-400}
REP=${REP:-1}
TILE=${TILE:-32}
DECOMP=${DECOMP:-blocks}
LAUNCH=${LAUNCH:-srun --cpu-bind=cores}
REFERENCE=0xb8683c550fa95bd6        # E1 checksum for 8192 x 8192, 400 steps, 16 ignitions
if [[ "$NX" != 8192 || "$STEPS" != 400 ]]; then
    echo "this job checks the E1 checksum, so it only runs NX=8192 STEPS=400" >&2
    exit 1
fi

source slurm/job_helpers.sh

module purge
module load OpenMPI/4.1.6-GCC-13.2.0 || exit 1   # not the node's own Open MPI 5.0.7
echo "mpicc: $(command -v mpicc)  mpirun: $(command -v mpirun)"
mpirun --version 2>&1 | head -n 1

# same MPI path as E5, E3, E4 and E7 (UCX crashed at start-up on two nodes, see REPRODUCE.md)
if [ "${MPI_DEFAULTS:-0}" != 1 ]; then
    export OMPI_MCA_pml=${OMPI_MCA_pml:-ob1}
    export OMPI_MCA_btl=${OMPI_MCA_btl:-self,vader,tcp}
    export OMPI_MCA_btl_vader_backing_directory=${OMPI_MCA_btl_vader_backing_directory:-/tmp}
fi
echo "MPI settings: $(env | grep '^OMPI_MCA_' | sort | tr '\n' ' ')"

export OMP_NUM_THREADS=1 OMP_PROC_BIND=close OMP_PLACES=cores

bin=./build/firefront_mpi
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run slurm/build.sbatch first"
    exit 1
fi

echo "rep=$REP tile=$TILE decomp=$DECOMP ranks=$SLURM_NTASKS nodes=$SLURM_JOB_NUM_NODES nodelist=$SLURM_JOB_NODELIST"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

args=(--nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42 --ignitions 16 --decomp "$DECOMP" --overlap 0)
order=(0 "$TILE")
(( REP % 2 == 0 )) && order=("$TILE" 0)

read -r -a launcher <<< "$LAUNCH"
bad=0
for skip in "${order[@]}"; do
    echo "== run: $SLURM_NTASKS ranks, --skip-tiles $skip =="
    echo "command: ${launcher[*]} $bin ${args[*]} --skip-tiles $skip"
    out=$("${launcher[@]}" "$bin" "${args[@]}" --skip-tiles "$skip") || bad=1
    line=$(printf '%s\n' "$out" | grep '^RESULT')
    if [[ "$line" == *"checksum=$REFERENCE"* && "$line" == *" ranks=$SLURM_NTASKS "* ]]; then
        printf '%s\n' "$out"
        echo "checksum ok"
    else
        printf '%s\n' "$out" | sed 's/^/FAILED OUTPUT: /'   # kept out of the RESULT parser
        bad=1
    fi
done
node_state end
exit $bad
