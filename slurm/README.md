# slurm

Job scripts. Every job runs **one repetition** (number from the `REP` environment variable, printed in the log as `rep=N`) and asks for **at most 10 minutes**. Parameters come from environment variables, so one script covers a whole series. The exact loop to launch each series is in a comment at the top of each script.

The scripts **build nothing**. On the login node, first run `make`, `make omp` and/or `make stream` (with the GCC module loaded), then submit from the repository root:

    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e1_baseline.sbatch; done

| script | what it runs |
|---|---|
| e1_baseline.sbatch | E1: serial, 8192², 400 steps, `--ignitions 16`, 1 core |
| e2_omp_threads.sbatch | E2 (OpenMP part): same problem, threads from `--cpus-per-task` (1, 2, 4 … 256 one per core, plus 512 on all hardware threads), `OMP_PROC_BIND=close`, whole node |
| stream.sbatch | STREAM triad, whole node, threads from `--cpus-per-task` (default 256 = all physical cores; same series as E2) |
| cluster_info_node.sbatch | `lscpu`, `numactl -H`, `nvidia-smi` on a compute node (1 task, 2 min) |
| serial.sbatch | general serial template, 1 core |
| omp.sbatch | general OpenMP template, threads from `--cpus-per-task` |
| hybrid.sbatch | MPI + OpenMP, 1 or 2 nodes (waits for `firefront_mpi`) |
| gpu.sbatch | CUDA build on one GPU (waits for `firefront_cuda`) |

Each job writes its log to `results/raw/<name>_<job id>.out` and an environment snapshot to `results/raw/env_<job id>.txt` (`tools/capture_env.sh`). If the binary is missing, the job stops with a message instead of building it.

All jobs run in partition `cpu` (GPU jobs in `gpu`) with account `hpcclass` and QOS `student`, and load the modules in `env/modules.txt`; the node layout (2 × 128 cores, 2 threads per core) is in `env/cluster.md`. E2 and STREAM reserve the whole node (`--exclusive`) because they measure or depend on the node's memory bandwidth, which other jobs would share; remove that line if the cluster does not allow it. E1 is a single core and asks only for that.
