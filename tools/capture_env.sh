#!/bin/bash
# Print a snapshot of the environment. Run it inside a job so it describes the node that did the work:
#   bash tools/capture_env.sh > results/raw/env_$SLURM_JOB_ID.txt

echo "date:      $(date -Is 2>/dev/null || date)"
echo "host:      $(hostname)"
echo "kernel:    $(uname -sr)"
echo "git:       $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "git dirty: $(git status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ') changed tracked files"
echo

echo "== slurm =="
env | grep -E '^SLURM_(JOB_ID|JOB_NAME|JOB_NODELIST|NNODES|NTASKS|NTASKS_PER_NODE|CPUS_PER_TASK|PARTITION)=' | sort
echo

echo "== openmp =="
env | grep -E '^OMP_' | sort
echo

echo "== compilers =="
for c in gcc mpicc nvcc nvc; do
    if command -v "$c" >/dev/null 2>&1; then
        echo "$c: $($c --version 2>&1 | head -n 1)"
    fi
done
command -v mpirun >/dev/null 2>&1 && echo "mpirun: $(mpirun --version 2>&1 | head -n 1)"
echo

echo "== modules =="
if command -v module >/dev/null 2>&1; then
    module list 2>&1
else
    echo "no module command"
fi
echo

echo "== cpu =="
command -v lscpu >/dev/null 2>&1 && lscpu | grep -E 'Model name|^CPU\(s\)|Thread|Core|Socket|NUMA|L2|L3'
command -v numactl >/dev/null 2>&1 && numactl --hardware | head -n 6
echo

echo "== gpu =="
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
else
    echo "no nvidia-smi"
fi
