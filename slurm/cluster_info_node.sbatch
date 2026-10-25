#!/bin/bash
# Hardware of a compute node (the login node can differ). Submit from the repository root:
#   sbatch slurm/cluster_info_node.sbatch
# For a GPU node, add the GPU partition and one GPU, e.g.
#   sbatch --partition=<gpu partition> --gres=gpu:1 slurm/cluster_info_node.sbatch
#SBATCH --job-name=ff-nodeinfo
#SBATCH --output=results/raw/cluster_info_node_%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:02:00

try() {
    if command -v "$1" >/dev/null 2>&1; then
        "$@" 2>&1
    else
        echo "not available ($1)"
    fi
}

echo "== hostname =="
hostname
echo "slurm job $SLURM_JOB_ID on partition ${SLURM_JOB_PARTITION:-?}"

echo
echo "== lscpu =="
try lscpu

echo
echo "== numactl -H =="
try numactl -H

echo
echo "== nvidia-smi =="
try nvidia-smi
