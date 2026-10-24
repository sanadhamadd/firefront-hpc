# env

Everything about the software environment lives here.

- `modules.txt`: the module names and versions we load on the cluster
- `requirements.txt`: Python packages for the analysis tools
- `tools/capture_env.sh` (in the tools folder) writes a snapshot of the environment next to each batch of results

First thing to do on the cluster: run `module avail`, `sinfo`, `srun --mpi=list` and `nvidia-smi -L`, and write what we find into `modules.txt`.
