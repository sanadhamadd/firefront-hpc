#!/bin/bash
# Submit all E8 jobs (tile skipping), 3 repetitions each, after a successful build:
#   - serial/OpenMP series on haskell (slurm/e8_skip_tiles.sbatch): 3 jobs
#   - MPI, blocks, one thread per rank (slurm/e8_skip_tiles_mpi.sbatch): 8, 16, 32 ranks on
#     haskell and 32 ranks as 2 x 16 over haskell and julia: 12 jobs
# The student QOS queues at most 8 jobs per user, so the script waits while 8 are queued;
# leave it running (e.g. in tmux). DRY_RUN=1 prints the commands only.
# Run from the repository root.
set -euo pipefail
reps=${REPS:-3}
owner=$(id -un)

submit() {
    if [[ "${DRY_RUN:-0}" == 1 ]]; then
        echo "sbatch $*"
        return
    fi
    while :; do
        queued=$(squeue -h -u "$owner" -o '%i' | wc -l)
        (( queued < 8 )) && break
        sleep 30
    done
    sbatch --parsable "$@"
}

for ((rep = 1; rep <= reps; rep++)); do
    submit --export="ALL,REP=$rep" slurm/e8_skip_tiles.sbatch
done
for ((rep = 1; rep <= reps; rep++)); do
    for ranks in 8 16 32; do
        submit --nodes=1 --ntasks="$ranks" --ntasks-per-node="$ranks" --nodelist=haskell \
            --export="ALL,REP=$rep" slurm/e8_skip_tiles_mpi.sbatch
    done
    submit --nodes=2 --ntasks=32 --ntasks-per-node=16 --nodelist=haskell,julia \
        --export="ALL,REP=$rep" slurm/e8_skip_tiles_mpi.sbatch
done
