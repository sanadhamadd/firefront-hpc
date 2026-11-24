#!/bin/bash
# E10, one repetition of the E1 problem on one RTX 6000 Ada.
# 8192 x 8192, 400 steps, 16 ignitions, seed 42. The checksum must be the serial one.
#
# This script builds nothing. Submit slurm/gpu_build.sbatch first and wait for
# "cuda checksums ok". From the repository root, three repetitions (one job each):
#   for rep in 1 2 3; do sbatch slurm/gpu.sbatch; done
# The student QOS allows 4 running jobs and 8 submitted in total (running + pending),
# so do not add the size sweep until these three have started or finished.
#SBATCH --job-name=ff-gpu
#SBATCH --output=results/raw/gpu_%j.out
#SBATCH --partition=gpu
#SBATCH --gres=gpu:rtx6000ada:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:15:00

NX=8192
NY=8192
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

echo "rep=${REP:-1}"
node_state start
job_resources
bash tools/capture_env.sh > results/raw/env_${SLURM_JOB_ID}.txt
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

args=(--nx "$NX" --ny "$NY" --steps "$STEPS" --seed "$SEED" --ignitions "$IGNITIONS")
if command -v cuda-exec >/dev/null 2>&1; then
    run=(cuda-exec "$bin")
else
    run=("$bin")
fi
echo "command: ${run[*]} ${args[*]}"
out=$("${run[@]}" "${args[@]}") || bad=1
line=$(printf '%s\n' "$out" | grep '^RESULT')
if [[ "${bad:-0}" -eq 0 && "$line" == *"checksum=$REFERENCE"* && "$line" == *"variant=cuda"* && "$line" == *"t_kernel="* ]]; then
    printf '%s\n' "$out"
    echo "checksum ok"
    node_state end
    exit 0
fi
printf '%s\n' "$out" | sed 's/^/FAILED OUTPUT: /'
echo "checksum FAILED (wanted $REFERENCE)"
node_state end
exit 1
