# slurm

Job scripts. Every job runs **one repetition** (number from the `REP` environment variable, printed in the log as `rep=N`) and asks for **at most 10 minutes**. Parameters come from environment variables. The exact loop to launch each series is in a comment at the top of each script.

The scripts **build nothing**. Build on a compute node first, wait for the job to finish and check its log (`all checks passed`, OpenMP lines `ok`), then submit from the repository root:

    sbatch slurm/build.sbatch
    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e1_baseline.sbatch; done

| script | what it runs |
|---|---|
| build.sbatch | `make clean`, `make`, `make omp`, `make stream`, `OMP_CC=gcc make test`, `make mpi`, `make test-mpi` (up to 8 ranks) on a compute node (8 CPUs) with the OpenMPI module; logs the `-march` gcc picks there and which `mpicc`/`mpirun` are used |
| e1_baseline.sbatch | E1: serial, 8192², 400 steps, `--ignitions 16`, 1 core |
| e2_omp_threads.sbatch | E2 (OpenMP part): same problem; one job = the whole series 1, 2, 4, 8, 16, 32 threads (one per core) plus 64 threads on the cores' hyper-threads |
| stream.sbatch | STREAM triad, same series as E2, 1.6e9 doubles (12.8 GB) |
| cluster_info_node.sbatch | `lscpu`, `numactl -H`, `nvidia-smi` on a compute node (1 task, 2 min) |
| serial.sbatch | general serial template, 1 core |
| omp.sbatch | general OpenMP template, threads from `--cpus-per-task` (at most 32) |
| mpi_check.sbatch | which MPI launcher works with the OpenMPI module (srun default / pmi2 / pmix, mpirun): small run on 4 ranks, compared with the serial checksum; also for 2 nodes |
| e5_decomp.sbatch | E5 and the MPI part of E2: pure MPI (1 thread per rank), 8192², 400 steps, 16 ignitions; ranks and nodes from the sbatch line, `DECOMP=strips\|blocks`; prints `checksum ok` if it matches E1 |
| submit_e5.sh | submits the E5 series (51 jobs) and waits whenever 8 jobs are queued; `DRY_RUN=1` only prints |
| hybrid.sbatch | MPI + OpenMP (E3), default 2 nodes × 4 ranks × 4 cores, `--overlap 0`, same problem as E1; prints `checksum ok` |
| gpu.sbatch | CUDA build on one GPU (waits for `firefront_cuda`) |
| size_sweep.sbatch | 32 threads, grids 2048², 4096², 8192², 16384²; second pass with `--humidity 1` (no spread); does the cache change the throughput? |
| job_helpers.sh | shared functions the jobs source: node state, job resources, run with `numastat` |

**Limits** (student QOS, see `env/cluster.md`): at most 64 CPUs per user at a time, which is 32 cores because Slurm counts both hardware threads of a core; at most 4 running and 8 queued jobs. E2 and STREAM therefore ask for `--cpus-per-task=64 --hint=multithread` (32 whole cores) and run their thread series inside one job. STREAM thus measures the bandwidth available to 32 cores, not to the whole node.

**Timing noise.** The cpu partition lets two jobs share the same cores (`OverSubscribe=FORCE:2`), and `--exclusive` cannot prevent that, so the scripts do not use it. Instead:
- build, E1, E2 and STREAM have the same job name and `--dependency=singleton`, so only one of them runs at a time and our own jobs never compete;
- every job logs the node, the load average and `squeue -w <node>` (our jobs as `self`, others as `other`, no user or job names) at the start and the end, plus the CPUs it really got (`NumCPUs`, usable CPU list, `numactl --show`);
- every run logs `numastat -p` of the program shortly before it ends (where its memory was placed);
- build, E1, E2 and STREAM are pinned to node haskell (`--nodelist`), so the `-march=native` build and all timed runs use the same CPU; E2 and STREAM also ask for one socket (`--sockets-per-node=1`), so their 32 cores stay in one NUMA domain (remove that line if jobs stay pending);
- E2 and STREAM print each thread's pinning (`OMP_DISPLAY_AFFINITY`).

Each job writes its log to `results/raw/<name>_<job id>.out` and an environment snapshot to `results/raw/env_<job id>.txt` (`tools/capture_env.sh`). If the binary is missing, the job stops with a message instead of building it. All jobs run in partition `cpu` (GPU jobs in `gpu`) with the default account and QOS, and load the modules in `env/modules.txt`.
