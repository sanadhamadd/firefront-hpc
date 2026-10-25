# Shared pieces of the Slurm job scripts. Sourced from the repository root:
#   source slurm/job_helpers.sh
#
# The cpu partition lets two jobs share the same cores (OverSubscribe=FORCE:2, see
# env/cluster.md), so every job writes down who else was on the node, to judge the
# timings afterwards.

# node name, load average and the other jobs on our node(s); call with "start" or "end"
node_state() {
    echo "== node state ($1) =="
    echo "node: $(hostname)"
    echo "time: $(date -Is 2>/dev/null || date)"
    echo "load: $(cat /proc/loadavg 2>/dev/null || uptime)"
    if command -v squeue >/dev/null 2>&1; then
        squeue -w "${SLURM_JOB_NODELIST:-$SLURMD_NODENAME}" -o "%.10i %.10P %.12j %.10u %.2t %.10M %.6C %.8m %R" 2>&1
    else
        echo "squeue: not available"
    fi
}

# which CPUs and how much this job really got, to check the request did what we meant
job_resources() {
    echo "== resources of this job =="
    if command -v taskset >/dev/null 2>&1; then
        echo "cpus usable: $(taskset -cp $$ 2>/dev/null | sed 's/.*: //')"
    fi
    if command -v numactl >/dev/null 2>&1; then
        numactl --show 2>/dev/null | grep -E 'physcpubind|nodebind|membind'
    fi
    if command -v scontrol >/dev/null 2>&1; then
        scontrol show job "$SLURM_JOB_ID" 2>/dev/null | grep -oE 'NumCPUs=[0-9]+|TRES=[^ ]+'
    fi
}

# Run a command. While it runs, take "numastat -p" of it every second and keep the
# latest one; after the run, print that last sample, i.e. how its memory was spread
# over the NUMA nodes shortly before the end.
run_logged() {
    echo "command: $*"
    "$@" &
    local pid=$! snap="" s
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        if command -v numastat >/dev/null 2>&1; then
            s=$(numastat -p "$pid" 2>/dev/null) && [ -n "$s" ] && snap=$s
        fi
    done
    wait "$pid"
    local status=$?
    echo "== numastat -p, last sample before the end of the run =="
    if [ -n "$snap" ]; then
        echo "$snap"
    else
        echo "no sample (run shorter than 1 s, or numastat not available)"
    fi
    return $status
}
