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

`make omp` needs gcc with OpenMP: on the cluster, load a GCC module first; on a Mac, pass Homebrew's GCC, e.g. `make CC=gcc-16 omp` and `OMP_CC=gcc-16 make test`. If the compiler has no OpenMP, the OpenMP test prints `skipped` instead of failing, so check that it really ran.

The MPI and GPU builds will be added with their sources.

## 4. Run an experiment

First, find out what the cluster has (safe on the login node; the job looks at a compute node):

    bash tools/cluster_info.sh > env/cluster_info_login.txt
    sbatch slurm/cluster_info_node.sbatch

The modules are in `env/modules.txt` (GCC 13.2.0; `module load GCC/13.2.0` before building). Job scripts are in `slurm/`. They build nothing, so run `make`, `make omp` and `make stream` on the login node first, then submit from the repository root. Each job is one repetition (`REP`), at most 10 minutes:

    # E1 baseline: serial, 8192², 400 steps, 16 ignitions
    for rep in 1 2 3; do sbatch --export=ALL,REP=$rep slurm/e1_baseline.sbatch; done
    # E2, OpenMP part: 1 to 256 threads (one per physical core), plus 512 on all hardware threads
    for rep in 1 2 3; do
      for t in 1 2 4 8 16 32 64 128 256; do sbatch --cpus-per-task=$t --export=ALL,REP=$rep slurm/e2_omp_threads.sbatch; done
      sbatch --cpus-per-task=512 --hint=multithread --export=ALL,REP=$rep slurm/e2_omp_threads.sbatch
    done
    # STREAM triad, memory bandwidth for the roofline, same thread series
    for rep in 1 2 3; do
      for t in 1 2 4 8 16 32 64 128 256; do sbatch --cpus-per-task=$t --export=ALL,REP=$rep slurm/stream.sbatch; done
      sbatch --cpus-per-task=512 --hint=multithread --export=ALL,REP=$rep slurm/stream.sbatch
    done

A node has 2 sockets × 128 cores × 2 hardware threads (see `env/cluster.md`). Up to 256 threads run one per core (`--hint=nomultithread`, `OMP_PLACES=cores`); the 512 run overrides that with `--hint=multithread` and the script switches to `OMP_PLACES=threads`.

## 5. Collect results and make figures

    python tools/parse_logs.py results/raw > results/tables/all.csv
    python tools/make_plots.py results/tables/all.csv results/figures

## What gets recorded for every run

Git commit, compiler and flags, loaded modules, random seed, Slurm resources, the exact command line and the OpenMP settings. Each run prints one `RESULT` line that the parsing script reads. The environment snapshot is saved next to the log.
