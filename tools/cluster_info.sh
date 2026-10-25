#!/bin/bash
# What does the cluster have? Safe to run on the login node: it only asks Slurm,
# the module system and the hardware for information and starts no jobs.
#
#   bash tools/cluster_info.sh > env/cluster_info_login.txt
#
# The login node can have a different CPU from the compute nodes. For those, run
#   sbatch slurm/cluster_info_node.sbatch
# Commands that do not exist print "not available" instead of failing.

section() {
    echo
    echo "== $1 =="
}

# run a command if it exists, otherwise say so
try() {
    if command -v "$1" >/dev/null 2>&1; then
        "$@" 2>&1
    else
        echo "not available ($1)"
    fi
}

# in a script, "module" is often not defined yet; load it the way login shells do
if ! type module >/dev/null 2>&1; then
    for f in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh \
             /usr/share/lmod/lmod/init/bash /usr/share/Modules/init/bash; do
        if [ -f "$f" ]; then
            # shellcheck disable=SC1090
            source "$f" >/dev/null 2>&1
            break
        fi
    done
fi

section "hostname"
hostname
date

section "sinfo (partition, available, time limit, nodes, cpus per node, memory MB, gres)"
try sinfo -o "%P %a %l %D %c %m %G"

section "scontrol show partition"
try scontrol show partition

section "lscpu (this node: the login node if run there)"
try lscpu

section "numactl -H"
try numactl -H

section "module avail, filtered for GCC, OpenMPI, CUDA, NVHPC, LIKWID"
if type module >/dev/null 2>&1; then
    # -t prints one module per line, so grep can filter it
    out=$(module -t avail 2>&1 | grep -iE 'gcc|openmpi|cuda|nvhpc|likwid')
    if [ -n "$out" ]; then echo "$out"; else echo "none of these found"; fi
else
    echo "not available (module)"
fi

section "srun --mpi=list"
try srun --mpi=list

section "nvidia-smi -L"
try nvidia-smi -L
