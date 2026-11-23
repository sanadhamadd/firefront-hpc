#!/bin/bash
# OpenACC multicore fallback: the E1 problem on 32 physical cores of haskell,
# the same budget as E2. Use this if the GPU queue does not start.
# The binary comes from slurm/acc_mc_build.sbatch, or from slurm/acc_build.sbatch.
# One repetition:
#   for rep in 1 2 3; do sbatch slurm/acc_mc.sbatch; done
# Each job asks for 64 CPUs (32 cores). That is the whole per-user budget,
# so these three must not run beside a 64-CPU CPU job.
#SBATCH --job-name=ff-acc-mc
#SBATCH --output=results/raw/acc_mc_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64
#SBATCH --hint=multithread
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --nodelist=haskell

REFERENCE=0xb8683c550fa95bd6

source slurm/job_helpers.sh

module purge
module load nvhpc/25.7 || exit 1
export ACC_NUM_CORES=32

bin=./build/firefront_acc_mc
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run slurm/acc_build.sbatch first"
    exit 1
fi

echo "rep=${REP:-1}"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt

args=(--nx 8192 --ny 8192 --steps 400 --seed 42 --ignitions 16)
echo "command: $bin ${args[*]}"
out=$("$bin" "${args[@]}") || bad=1
line=$(printf '%s\n' "$out" | grep '^RESULT')
if [[ "${bad:-0}" -eq 0 && "$line" == *"checksum=$REFERENCE"* && "$line" == *"variant=accmc"* ]]; then
    printf '%s\n' "$out"
    echo "checksum ok"
    node_state end
    exit 0
fi
printf '%s\n' "$out" | sed 's/^/FAILED OUTPUT: /'
echo "checksum FAILED (wanted $REFERENCE)"
node_state end
exit 1
