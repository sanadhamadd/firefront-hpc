#!/bin/bash
# Run from the repository root after the compute-node build succeeds.
set -euo pipefail
reps=${REPS:-5}
decomp=${DECOMP:-blocks}
[[ "$reps" =~ ^[1-9][0-9]*$ && "$reps" -le 99 ]]
[[ "$decomp" == blocks || "$decomp" == strips ]]
mkdir -p results/raw/e7-e9
owner=$(id -un)

for nodes in 1 2; do
    nodelist=haskell
    ranks=(4 8 16 32)
    if (( nodes == 2 )); then
        nodelist=haskell,julia
        ranks=(8 16 32)
    fi
    for total in "${ranks[@]}"; do
        for ((rep=1; rep<=reps; rep++)); do
            while :; do
                queued=$(squeue -h -u "$owner" -o '%i')
                [[ -z "$queued" ]] && break
                [[ $(wc -l <<< "$queued") -lt 8 ]] && break
                sleep 30
            done
            printf '%s node(s), %s ranks, repetition %s: ' "$nodes" "$total" "$rep"
            sbatch --parsable --nodes="$nodes" --ntasks="$total" \
                --ntasks-per-node="$((total / nodes))" --nodelist="$nodelist" \
                --export="ALL,DECOMP=$decomp,REP=$rep,PROFILE=none,VERIFY_ONLY=0" slurm/e7_overlap.sbatch
        done
    done
done
