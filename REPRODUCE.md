# Reproducing the results

This file will contain the exact commands for every main figure in the report. It is filled in step by step as the experiments are done. Nothing below has been run yet.

## 1. Get the code

    git clone https://github.com/sanadhamadd/firefront-hpc.git
    cd firefront-hpc

## 2. Environment

On the cluster: load the modules listed in `env/modules.txt`, then check what you have with

    bash tools/capture_env.sh

For the Python tools:

    pip install -r env/requirements.txt

## 3. Build

    make            # serial version, build/firefront_serial
    make test       # checks, including OpenMP vs serial checksum (compiler from OMP_CC, default gcc)
    make omp        # OpenMP version, build/firefront_omp
    make stream     # STREAM triad, build/stream (memory bandwidth for the roofline)

On the cluster, build on a compute node, not on the login node (a small virtual machine without AVX, so `-march=native` there would target the wrong CPU):

    sbatch slurm/build.sbatch      # make clean, make, make omp, make stream, OMP_CC=gcc make test

Wait for it to finish and check `results/raw/build_<job id>.out`: it must end with `all checks passed`, and the OpenMP lines must say `ok`, not `skipped`. The log also shows which `-march` gcc picked on the node.

`make omp` needs gcc with OpenMP: on the cluster `module load GCC/13.2.0` (the build job does this); on a Mac, pass Homebrew's GCC, e.g. `make CC=gcc-16 omp` and `OMP_CC=gcc-16 make test`. If the compiler has no OpenMP, the OpenMP test prints `skipped` instead of failing, so check that it really ran.

The MPI and GPU builds will be added with their sources.

## 4. Run an experiment

First, find out what the cluster has (safe on the login node; the job looks at a compute node):

    bash tools/cluster_info.sh > env/cluster_info_login.txt
    sbatch slurm/cluster_info_node.sbatch

The modules are in `env/modules.txt`, the cluster and its limits in `env/cluster.md`. Job scripts are in `slurm/`; they build nothing (see section 3). Submit from the repository root. Each job is one repetition (`REP`), at most 10 minutes. At most 8 jobs may be queued per user, so submit in two parts:

    # part 1 (7 jobs): build, then E1 and E2
    sbatch slurm/build.sbatch
    # E1 baseline: serial, 8192², 400 steps, 16 ignitions, 1 core
    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e1_baseline.sbatch; done
    # E2, OpenMP part: each job runs 1, 2, 4, 8, 16, 32 threads (one per core) and 64 (hyper-threads)
    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e2_omp_threads.sbatch; done

    # part 2, when the queue has room: STREAM, same thread series
    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/stream.sbatch; done

The student QOS allows 64 CPUs per user, which is 32 physical cores, so no run uses more than 32 cores (MPI on 2 nodes: at most 2 × 16 cores). E2 and STREAM ask for exactly that (`--cpus-per-task=64 --hint=multithread`) on one socket (`--sockets-per-node=1`). Build, E1, E2 and STREAM all run on node haskell (`--nodelist=haskell`), so the `-march=native` build and every timed run use the same CPU. Each RESULT line ends with `places=cores` or `places=threads`; `make_plots.py` counts physical cores from it and draws the 64-thread hyper-thread run as a separate star. Build, E1, E2 and STREAM share one job name and use `--dependency=singleton`, so they run one after another in the order submitted and never share cores with each other; other users' jobs still can (`OverSubscribe=FORCE:2`), so every log records the node, the load and `squeue -w <node>` at the start and the end, and `numastat -p` of each run. E2 takes about 4–5 minutes per job (estimate from the laptop E1 time, assuming a cluster core up to 2× slower).

## 5. Collect results and make figures

    python tools/parse_logs.py results/raw > results/tables/all.csv
    python tools/make_plots.py results/tables/all.csv results/figures

## What gets recorded for every run

Git commit, compiler and flags, loaded modules, random seed, Slurm resources, the exact command line and the OpenMP settings. Each run prints one `RESULT` line that the parsing script reads. The environment snapshot is saved next to the log.
