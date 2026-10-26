#!/bin/bash
# Which way of starting MPI programs works with our OpenMPI module? Run this once, after
# slurm/build.sbatch, before any timed MPI job.
#
# Slurm can start MPI ranks itself (srun, with a PMI plugin), or the module's mpirun can.
# srun --mpi=list on the cluster offers none, pmi2, cray_shasta and pmix; which of them
# our OpenMPI 4.1.6 accepts is not known yet. Each launcher runs a small problem on 4 ranks
# and must print the serial checksum. The log ends with a summary; put the first launcher
# that works into LAUNCH for the timed jobs (slurm/e5_decomp.sbatch, slurm/hybrid.sbatch).
#
# One node (default):  sbatch slurm/mpi_check.sbatch
# Two nodes (also checks julia can run the binary built on haskell):
#   sbatch --nodes=2 --ntasks-per-node=2 --nodelist=haskell,julia slurm/mpi_check.sbatch
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/mpi_check_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH --mem-per-cpu=1G
#SBATCH --time=00:05:00
#SBATCH --dependency=singleton
#SBATCH --nodelist=haskell

source slurm/job_helpers.sh

module purge
module load OpenMPI/4.1.6-GCC-13.2.0 || exit 1   # also loads GCC/13.2.0, see env/modules.txt
echo "mpicc: $(command -v mpicc)  mpirun: $(command -v mpirun)"
mpirun --version 2>&1 | head -n 1
echo "== PMI support of the OpenMPI module =="
ompi_info 2>/dev/null | grep -i -E 'pmi|slurm' | head -n 20
echo "== srun --mpi=list =="
srun --mpi=list 2>&1 | head -n 10

for b in build/firefront_serial build/firefront_mpi; do
    if [ ! -x "$b" ]; then
        echo "$b is missing: run slurm/build.sbatch first"
        exit 1
    fi
done

node_state start
job_resources

args=(--nx 512 --ny 512 --steps 100 --seed 42 --ignitions 16)
want=$(build/firefront_serial "${args[@]}" | grep '^RESULT' | sed 's/.*checksum=\(0x[0-9a-f]*\).*/\1/')
echo "serial checksum: $want"

export OMP_NUM_THREADS=1
launchers=("srun --cpu-bind=cores" "srun --mpi=pmi2 --cpu-bind=cores" "srun --mpi=pmix --cpu-bind=cores" "mpirun --bind-to core")
summary=""
for launch in "${launchers[@]}"; do
    echo "== $launch =="
    out=$(timeout 60 $launch build/firefront_mpi "${args[@]}" --decomp blocks 2>&1)
    echo "$out" | tail -n 4
    got=$(echo "$out" | grep '^RESULT' | sed 's/.*checksum=\(0x[0-9a-f]*\).*/\1/')
    ranks=$(echo "$out" | grep '^RESULT' | sed 's/.* ranks=\([0-9]*\).*/\1/')
    nodes=$(echo "$out" | grep '^RESULT' | sed 's/.* nodes=\([0-9]*\).*/\1/')
    if [ -n "$got" ] && [ "$got" = "$want" ] && [ "$ranks" = "$SLURM_NTASKS" ]; then
        summary="$summary\nworks:  $launch  ($ranks ranks on $nodes node(s), checksum $got)"
    else
        summary="$summary\nfails:  $launch  (ranks=${ranks:-none}, checksum=${got:-none})"
    fi
done

echo "== summary (want $SLURM_NTASKS ranks, checksum $want) =="
echo -e "$summary"
node_state end
