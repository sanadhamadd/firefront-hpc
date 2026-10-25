# env

Everything about the software environment lives here.

- `modules.txt`: the module names and versions we load on the cluster
- `requirements.txt`: Python packages for the analysis tools
- `tools/capture_env.sh` writes a snapshot of the environment next to each batch of results

First thing to do on the cluster: run `bash tools/cluster_info.sh` on the login node (partitions, CPU, modules, MPI plugins, GPUs) and `sbatch slurm/cluster_info_node.sbatch` for a compute node, then write what we find into `modules.txt` and replace the `TODO` placeholders in `slurm/`.
