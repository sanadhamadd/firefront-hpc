# slurm

Job templates. They take their parameters from environment variables so one script covers a whole series:

    sbatch --export=ALL,NX=8192,STEPS=500 slurm/omp.sbatch

| script | what it runs |
|---|---|
| serial.sbatch | baseline, 1 core |
| omp.sbatch | OpenMP, 1 node, threads from `--cpus-per-task` |
| hybrid.sbatch | MPI + OpenMP, 1 or 2 nodes |
| gpu.sbatch | CUDA build on one GPU |

All of them write their log to `results/raw/` and save an environment snapshot next to it. The binaries are built into `build/` (the Makefile will be added together with the first source files).
