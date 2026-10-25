#!/bin/bash
# Grid size sweep at 32 threads: does the cache change the throughput?
# One repetition per job. Each job runs, one after another, at 32 threads (one per core,
# OMP_PLACES=cores, OMP_PROC_BIND=close) and 400 steps with 16 ignitions:
#   pass 1, model defaults:    2048^2, 4096^2, 8192^2, 16384^2
#   pass 2, --humidity 1:      the same four sizes
# Every run prints its own RESULT line.
#
# This script builds nothing: run slurm/build.sbatch first.
# Submit from the repository root. Whole series (3 repetitions = 3 jobs):
#   for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/size_sweep.sbatch; done
#
# What to expect. Far from the fire a cell update streams its state byte, its fuel and
# the new state byte, so one step streams about 6 bytes per cell. Per step that is
# 25 MB at 2048^2, 101 MB at 4096^2, 403 MB at 8192^2 and 1.6 GB at 16384^2. With 32
# threads, a chiplet of 8 cores gets a quarter of that; its L3 holds 32 MB. So 2048^2
# and 4096^2 can stay in cache between steps, 8192^2 and 16384^2 cannot. If the small
# grids give clearly more MCUPS than the large ones, memory traffic limits the large
# grids; if all four are about the same, the cell update itself (hash, branches) does.
#
# Why the second pass: with the default humidity, 400 steps burn about 30% of a 2048^2
# grid but only 2% of an 8192^2 grid, and burnt cells are cheaper, which would favour
# the small grids. With --humidity 1 the fire cannot spread (ignition probability 0), so
# on every grid nearly every cell is "unburnt, no burning neighbour" and does the same
# work. That pass compares the sizes on equal terms.
#
# Note: the RESULT line has no humidity field, so the two passes can only be told apart
# by their order in the log (pass 1 first) or by their burnt count (about 144 cells with
# --humidity 1, the 16 starting patches).
#
# Resources as in E2: 32 whole cores on one socket of haskell (--cpus-per-task=64 with
# --hint=multithread counts both hardware threads). 16384^2 needs 2.7 GB, so --mem=4G.
# Time: about 1 + 1 + 3 + 13 s per pass at 8000 MCUPS, plus setting up the grids, well
# under a minute per job. Same job name as the other timed jobs, so with
# --dependency=singleton they run one at a time.
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/size_sweep_%j.out
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

STEPS=${STEPS:-400}
REP=${REP:-1}
SIZES=${SIZES:-"2048 4096 8192 16384"}

source slurm/job_helpers.sh

module purge
module load GCC/13.2.0 || exit 1   # see env/modules.txt

bin=./build/firefront_omp
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run slurm/build.sbatch first"
    exit 1
fi

echo "rep=$REP"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

export OMP_DISPLAY_AFFINITY=true
export OMP_AFFINITY_FORMAT="thread %n of %N on cpus %A"
export OMP_PROC_BIND=close OMP_PLACES=cores OMP_NUM_THREADS=32

for n in $SIZES; do
    echo "== pass 1 (model defaults): ${n}^2, 32 threads =="
    run_logged "$bin" --nx "$n" --ny "$n" --steps "$STEPS" --seed 42 --ignitions 16
done
for n in $SIZES; do
    echo "== pass 2 (--humidity 1, no spread): ${n}^2, 32 threads =="
    run_logged "$bin" --nx "$n" --ny "$n" --steps "$STEPS" --seed 42 --ignitions 16 --humidity 1
done

node_state end
