#!/bin/bash
# E10 OpenACC on one RTX 6000 Ada, one repetition of the E1 problem.
# Submit only after slurm/acc_build.sbatch prints "acc checksums ok".
#   for rep in 1 2 3; do sbatch slurm/acc.sbatch; done
#SBATCH --job-name=ff-acc
#SBATCH --output=results/raw/acc_%j.out
#SBATCH --partition=gpu
#SBATCH --gres=gpu:rtx6000ada:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:15:00

REFERENCE=0xb8683c550fa95bd6

source slurm/job_helpers.sh

module purge
module load nvhpc/25.7 || exit 1

bin=./build/firefront_acc
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run slurm/acc_build.sbatch first"
    exit 1
fi

echo "rep=${REP:-1}"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

args=(--nx 8192 --ny 8192 --steps 400 --seed 42 --ignitions 16)
echo "command: $bin ${args[*]}"
out=$("$bin" "${args[@]}") || bad=1
line=$(printf '%s\n' "$out" | grep '^RESULT')
if [[ "${bad:-0}" -eq 0 && "$line" == *"checksum=$REFERENCE"* && "$line" == *"variant=acc"* ]]; then
    printf '%s\n' "$out"
    echo "checksum ok"
    node_state end
    exit 0
fi
printf '%s\n' "$out" | sed 's/^/FAILED OUTPUT: /'
echo "checksum FAILED (wanted $REFERENCE)"
node_state end
exit 1
