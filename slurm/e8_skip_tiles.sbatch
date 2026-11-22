#!/bin/bash
# E8 kernel optimisation, serial and OpenMP part: skip tiles with no fire nearby
# (--skip-tiles T). Same problem as E1/E2: 8192 x 8192, 400 steps, 16 ignitions, seed 42.
# One repetition per job. Before and after run in the same job, on the same 32 cores:
#   1. serial, no skipping (the E1 baseline again)  and  serial, --skip-tiles 32
#   2. 32 threads, no skipping (the E2 point again)  and  32 threads, --skip-tiles 8 16 32 64 128
#      (tile size is the sensitivity parameter)
#   3. thread scaling of the optimised code: 1, 2, 4, 8, 16 threads with --skip-tiles 32
# Every run prints its own RESULT line with skip_tiles= and active_tiles= (share of the
# tile updates that were computed). Every run must print checksum=0xb8683c550fa95bd6.
#
# This script builds nothing: run slurm/build.sbatch first (it builds both binaries).
# Submit from the repository root. Whole series (3 repetitions = 3 jobs):
#   for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e8_skip_tiles.sbatch; done
#
# Time: the serial run without skipping takes about 82 s (E1); everything else together
# about 15 s plus start-up, so a job needs about 3 minutes.
# Resources, node and pinning as E2 (slurm/e2_omp_threads.sbatch): 32 whole cores of one
# socket on haskell, one thread per core, one timed job at a time (singleton).
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/e8_skip_tiles_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64
#SBATCH --hint=multithread
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --dependency=singleton
#SBATCH --nodelist=haskell
#SBATCH --sockets-per-node=1

NX=${NX:-8192}
STEPS=${STEPS:-400}
REP=${REP:-1}
TILE=${TILE:-32}

source slurm/job_helpers.sh

module purge
module load GCC/13.2.0 || exit 1   # see env/modules.txt

for bin in ./build/firefront_serial ./build/firefront_omp; do
    if [ ! -x "$bin" ]; then
        echo "$bin is missing: run slurm/build.sbatch first"
        exit 1
    fi
done
if ! ./build/firefront_serial --help | grep -q -- --skip-tiles; then
    echo "the binaries are older than --skip-tiles: rebuild with slurm/build.sbatch"
    exit 1
fi

cpus=${SLURM_CPUS_PER_TASK:-64}
cores=$((cpus / 2))

echo "rep=$REP tile=$TILE"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

export OMP_DISPLAY_AFFINITY=true
export OMP_AFFINITY_FORMAT="thread %n of %N on cpus %A"
export OMP_PROC_BIND=close OMP_PLACES=cores
args=(--nx "$NX" --ny "$NX" --steps "$STEPS" --seed 42 --ignitions 16)

echo "== run: serial, no skipping =="
run_logged ./build/firefront_serial "${args[@]}"
echo "== run: serial, --skip-tiles $TILE =="
run_logged ./build/firefront_serial "${args[@]}" --skip-tiles "$TILE"

export OMP_NUM_THREADS=$cores
echo "== run: $cores threads, no skipping =="
run_logged ./build/firefront_omp "${args[@]}"
for t in 8 16 32 64 128; do
    echo "== run: $cores threads, --skip-tiles $t =="
    run_logged ./build/firefront_omp "${args[@]}" --skip-tiles "$t"
done

for ((t = 1; t < cores; t *= 2)); do
    echo "== run: $t thread(s), --skip-tiles $TILE =="
    export OMP_NUM_THREADS=$t
    run_logged ./build/firefront_omp "${args[@]}" --skip-tiles "$TILE"
done

node_state end
