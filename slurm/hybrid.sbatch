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
NY=${NY:-$NX}
STEPS=${STEPS:-400}
DECOMP=${DECOMP:-blocks}
OVERLAP=${OVERLAP:-0}
REP=${REP:-1}
LAUNCH=${LAUNCH:-srun --cpu-bind=cores}
REFERENCE=${REFERENCE:-}
if [[ "$NX" = 8192 && "$NY" = 8192 && "$STEPS" = 400 ]]; then
    if [[ -n "$REFERENCE" && "$REFERENCE" != 0xb8683c550fa95bd6 ]]; then
        echo "CHECKSUM ERROR: supplied reference disagrees with E1" >&2
        exit 1
    fi
    REFERENCE=0xb8683c550fa95bd6
fi

source slurm/job_helpers.sh

module purge
# The node also has a system mpirun (Open MPI 5.0.7). Build and run must use this module's MPI,
# so load it before srun and check in the log that mpicc/mpirun come from it (env/cluster.md).
module load OpenMPI/4.1.6-GCC-13.2.0 || exit 1   # also loads GCC/13.2.0, see env/modules.txt
echo "mpicc: $(command -v mpicc)  mpirun: $(command -v mpirun)"
mpirun --version 2>&1 | head -n 1

# Open MPI's default network layer (UCX) crashed at start-up in 2-node runs on this cluster
# (jobs 32004, 32014, 32015, 32025-32027: "sm BTL initialization" error, then a segfault in
# libucs, before our code ran). The ob1 layer with shared memory and TCP ran the same setups
# correctly (jobs 32028-32030), so every MPI run uses it, also on one node, to keep the
# timings comparable. MPI_DEFAULTS=1 goes back to Open MPI's own choice.
if [ "${MPI_DEFAULTS:-0}" != 1 ]; then
    export OMPI_MCA_pml=${OMPI_MCA_pml:-ob1}
    export OMPI_MCA_btl=${OMPI_MCA_btl:-self,vader,tcp}
    export OMPI_MCA_btl_vader_backing_directory=${OMPI_MCA_btl_vader_backing_directory:-/tmp}
fi
echo "MPI settings: $(env | grep '^OMPI_MCA_' | sort | tr '\n' ' ')"

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=close
export OMP_PLACES=cores

bin=./build/firefront_mpi
if [ ! -x "$bin" ]; then
    echo "$bin is missing: build the MPI version first"
    exit 1
fi

echo "rep=$REP experiment=${EXPERIMENT:-} nx=$NX ny=$NY steps=$STEPS"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

echo "decomp=$DECOMP ranks=$SLURM_NTASKS threads=$OMP_NUM_THREADS nodes=$SLURM_JOB_NUM_NODES nodelist=$SLURM_JOB_NODELIST"
args=(--nx "$NX" --ny "$NY" --steps "$STEPS" --seed 42 --ignitions 16)
validate=(python3 tools/phase3a_results.py check "$NX" "$NY" "$STEPS")
if [[ -z "$REFERENCE" ]]; then
    if [[ ! -x ./build/firefront_serial ]]; then
        echo "CHECKSUM ERROR: build the serial executable or supply REFERENCE" >&2
        exit 1
    fi
    # Dedicated one-task step, outside the benchmark's timed region.
    serial=$(srun --mpi=none --exact -N1 -n1 --ntasks-per-node=1 -c1 ./build/firefront_serial "${args[@]}") || exit 1
    REFERENCE=$(printf '%s\n' "$serial" | "${validate[@]}" serial) || exit 1
fi
echo "serial checksum: $REFERENCE"

read -r -a launcher <<< "$LAUNCH"
if [[ "$LAUNCH" = "mpirun --bind-to core" ]]; then
    ranks_per_node=$((SLURM_NTASKS / SLURM_JOB_NUM_NODES))
    launcher+=(--map-by "ppr:${ranks_per_node}:node:PE=${OMP_NUM_THREADS}" -np "$SLURM_NTASKS")
fi
echo "command: ${launcher[*]} $bin ${args[*]} --decomp $DECOMP --overlap $OVERLAP"
out=$("${launcher[@]}" "$bin" "${args[@]}" --decomp "$DECOMP" --overlap "$OVERLAP")
status=$?
# Keep failed output for diagnosis without exposing it to generic RESULT parsers.
if (( status != 0 )); then
    printf '%s\n' "$out" | sed 's/^/FAILED OUTPUT: /'
    exit "$status"
fi
if ! printf '%s\n' "$out" | "${validate[@]}" mpi "$REFERENCE" "$SLURM_NTASKS" \
    "$OMP_NUM_THREADS" "$SLURM_JOB_NUM_NODES" "$DECOMP" "$OVERLAP"; then
    printf '%s\n' "$out" | sed 's/^/FAILED OUTPUT: /'
    exit 1
fi
printf '%s\n' "$out"
echo "checksum ok"
node_state end
exit 0
