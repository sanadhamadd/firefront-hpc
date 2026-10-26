#!/bin/bash
# Submit the E5 series (strips vs blocks) plus the small rank counts of the MPI strong
# scaling, one job per configuration and repetition. Run on the login node from the
# repository root, after slurm/build.sbatch and slurm/mpi_check.sbatch:
#   bash slurm/submit_e5.sh                 # everything below, 3 repetitions
#   REPS="1" bash slurm/submit_e5.sh        # one repetition first, to look at the numbers
#   DRY_RUN=1 bash slurm/submit_e5.sh       # only print the sbatch commands
#   LAUNCH="srun --mpi=pmix --cpu-bind=cores" bash slurm/submit_e5.sh   # if mpi_check says so
#
# The student QOS allows only 8 queued jobs per user, so the script waits until the queue
# has room before each sbatch (it checks every 30 s; leave it running, e.g. in tmux, or
# submit in parts with REPS). The jobs then run one after another (singleton dependency).

REPS=${REPS:-1 2 3}
ONE_NODE_RANKS=${ONE_NODE_RANKS:-1 2 4 8 16 32}
TWO_NODE_RANKS=${TWO_NODE_RANKS:-8 16 32}
DECOMPS=${DECOMPS:-strips blocks}
MAX_QUEUED=${MAX_QUEUED:-8}
export LAUNCH=${LAUNCH:-srun --cpu-bind=cores}

wait_for_room() {
    [ -n "$DRY_RUN" ] && return
    while [ "$(squeue -h -u "$USER" | wc -l)" -ge "$MAX_QUEUED" ]; do
        sleep 30
    done
}

submit() {   # nodes ranks_per_node nodelist decomp rep
    local cmd=(sbatch --nodes="$1" --ntasks-per-node="$2" --nodelist="$3"
               --export=ALL,DECOMP="$4",REP="$5" slurm/e5_decomp.sbatch)
    if [ -n "$DRY_RUN" ]; then
        echo "${cmd[*]}"
    else
        wait_for_room
        "${cmd[@]}"
    fi
}

for rep in $REPS; do
    for decomp in $DECOMPS; do
        for np in $ONE_NODE_RANKS; do
            # with 1 rank strips and blocks are the same run; do it once
            if [ "$np" = 1 ] && [ "$decomp" != strips ]; then continue; fi
            submit 1 "$np" haskell "$decomp" "$rep"
        done
        for np in $TWO_NODE_RANKS; do
            submit 2 $((np / 2)) haskell,julia "$decomp" "$rep"
        done
    done
done
