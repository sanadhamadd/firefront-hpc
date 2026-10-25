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

`make omp` needs gcc with OpenMP: on the cluster, load a GCC module first; on a Mac, pass Homebrew's GCC, e.g. `make CC=gcc-16 omp` and `OMP_CC=gcc-16 make test`. If the compiler has no OpenMP, the OpenMP test prints `skipped` instead of failing, so check that it really ran.

The MPI and GPU builds will be added with their sources.

## 4. Run an experiment

Job scripts are in `slurm/`. Parameters are passed as environment variables, for example

    sbatch --export=ALL,NX=8192,STEPS=500 slurm/omp.sbatch

## 5. Collect results and make figures

    python tools/parse_logs.py results/raw > results/tables/all.csv
    python tools/make_plots.py results/tables/all.csv results/figures

## What gets recorded for every run

Git commit, compiler and flags, loaded modules, random seed, Slurm resources, the exact command line and the OpenMP settings. Each run prints one `RESULT` line that the parsing script reads. The environment snapshot is saved next to the log.
