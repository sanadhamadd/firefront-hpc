#!/bin/bash
# Build everything on a compute node and run the tests there.
#
# Why not on the login node: it is a small virtual machine without AVX (env/cluster.md),
# so -march=native there would build for that CPU instead of the compute nodes' Zen 5.
# The log shows which -march gcc picks on the node.
#
# Submit from the repository root, wait for it to finish, and check that
# results/raw/build_<job id>.out ends with "all checks passed" and the OpenMP lines say "ok"
# before submitting timed jobs:
#   sbatch slurm/build.sbatch
#
# Same job name as the timed jobs (E1, E2, STREAM) on purpose: with --dependency=singleton
# only one job of that name runs at a time, so a build never replaces the binaries while a
# timed job is using them. If the build or a test fails, the binaries are deleted, so later
# timed jobs stop with "missing" instead of timing a broken build.
#
# Pinned to haskell (--nodelist): the -march=native build and every timed run then use
# the same CPU, and env/cluster.md describes that node (cluster_info was taken there).
# MPI: the OpenMPI/4.1.6-GCC-13.2.0 module is loaded (it brings GCC/13.2.0 with it). The node
# also has a system mpirun from Open MPI 5.0.7; the log shows which mpicc/mpirun are used,
# and both must come from the module. make test-mpi runs the MPI checks with up to 8 ranks
# on the 8 CPUs of this job (mpirun --oversubscribe).
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/build_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --dependency=singleton
#SBATCH --nodelist=haskell

source slurm/job_helpers.sh

module purge
module load OpenMPI/4.1.6-GCC-13.2.0 || exit 1   # also loads GCC/13.2.0, see env/modules.txt
echo "mpicc: $(command -v mpicc)  mpirun: $(command -v mpirun)"
mpirun --version 2>&1 | head -n 1

node_state start
echo "== -march that gcc picks on this node =="
gcc -march=native -Q --help=target | grep march

make clean && make && make omp && make stream && OMP_CC=gcc make test &&
    make mpi && MPIRUN="mpirun --oversubscribe" RANKS="1 2 3 4 8" make test-mpi
status=$?
if [ $status -ne 0 ]; then
    echo "BUILD OR TESTS FAILED: removing the binaries so no timed job uses them"
    rm -f build/firefront_serial build/firefront_omp build/firefront_mpi build/stream
fi

node_state end
exit $status
