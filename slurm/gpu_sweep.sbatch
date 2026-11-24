#!/bin/bash
# E10 size sweep, one grid size and one repetition per job. Same steps, seed and
# ignitions as E1. Grids: 1024, 2048, 4096, 8192, 16384. 8192 is also the timed
# E1 job; this script checks that size against the same reference.
#
# Builds nothing. After the three slurm/gpu.sbatch jobs are out of the queue
# (the QOS allows 8 submitted jobs in total), submit one wave at a time:
#   for n in 1024 2048 4096 16384; do sbatch --export=ALL,NX=$n slurm/gpu_sweep.sbatch; done
# Repeat for REP=2 and REP=3, still at most 8 jobs submitted.
#SBATCH --job-name=ff-gpu
#SBATCH --output=results/raw/gpu_sweep_%j.out
#SBATCH --partition=gpu
#SBATCH --gres=gpu:rtx6000ada:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=00:20:00

NX=${NX:-1024}
STEPS=400
SEED=42
IGNITIONS=16
REFERENCE=0xb8683c550fa95bd6

source slurm/job_helpers.sh

module purge
module load hpc-course-cuda/12.8.1 || exit 1

bin=./build/firefront_cuda
if [ ! -x "$bin" ]; then
    echo "$bin is missing: run slurm/gpu_build.sbatch first"
    exit 1
fi

echo "rep=${REP:-1} nx=$NX"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

args=(--nx "$NX" --ny "$NX" --steps "$STEPS" --seed "$SEED" --ignitions "$IGNITIONS")
if command -v cuda-exec >/dev/null 2>&1; then
    run=(cuda-exec "$bin")
else
    run=("$bin")
fi
echo "command: ${run[*]} ${args[*]}"
out=$("${run[@]}" "${args[@]}") || bad=1
line=$(printf '%s\n' "$out" | grep '^RESULT')
ok=0
note="checksum FAILED"
if [[ "${bad:-0}" -eq 0 && "$line" == *"variant=cuda"* && "$line" == *"t_kernel="* ]]; then
    if [[ "$NX" == 8192 ]]; then
        [[ "$line" == *"checksum=$REFERENCE"* ]] && ok=1
    elif [[ "$NX" -le 4096 ]]; then
        if [[ ! -x ./build/firefront_serial ]]; then
            note="checksum FAILED (build/firefront_serial is missing)"
        else
            want=$(./build/firefront_serial "${args[@]}" --verify-only | sed -n 's/^VERIFY //p')
            [[ -n "$want" && "$line" == *"$want"* ]] && ok=1
        fi
    else
        ok=1
        note="recorded (no serial run at this size; 8192 is the checksum gate)"
    fi
fi
if [[ "$ok" -eq 1 ]]; then
    printf '%s\n' "$out"
    [[ "$note" == "checksum FAILED" ]] && note="checksum ok"
    echo "$note"
    node_state end
    exit 0
fi
printf '%s\n' "$out" | sed 's/^/FAILED OUTPUT: /'
echo "checksum FAILED"
node_state end
exit 1
