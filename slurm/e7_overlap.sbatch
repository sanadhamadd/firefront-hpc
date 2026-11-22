#!/bin/bash
# One paired repetition per allocation. Set PROFILE=perf for a separate E9 run.
#SBATCH --job-name=firefront
#SBATCH --output=results/raw/e7-e9/e7_overlap_%j.out
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --dependency=singleton
#SBATCH --nodelist=haskell

set -eo pipefail
source slurm/job_helpers.sh
module purge
module load OpenMPI/4.1.6-GCC-13.2.0

export OMPI_MCA_pml=ob1 OMPI_MCA_btl=self,vader,tcp
export OMPI_MCA_btl_vader_backing_directory=/tmp
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}" OMP_DYNAMIC=FALSE
export OMP_PROC_BIND=close OMP_PLACES=cores

bin=./build/firefront_mpi
reference=0xb8683c550fa95bd6
profile=${PROFILE:-none}
verify_only=${VERIFY_ONLY:-0}
rep=${REP:-1}
decomp=${DECOMP:-blocks}
[[ -x "$bin" && "$rep" =~ ^[1-9][0-9]*$ && "$rep" -le 99 ]]
[[ "$decomp" == blocks || "$decomp" == strips ]]
[[ "$profile" == none || "$profile" == perf ]]
[[ "$verify_only" == 0 || "$verify_only" == 1 ]]
(( SLURM_NTASKS * OMP_NUM_THREADS <= 32 ))

rev=$(git rev-parse --short HEAD)
git diff --quiet HEAD -- src Makefile slurm/e7_overlap.sbatch
read -r binary_sha _ < <(sha256sum "$bin")
echo "PAIR rep=$rep profile=$profile commit=$rev binary_sha=$binary_sha transport=ob1/self,vader,tcp allocation=$SLURM_JOB_NODELIST"
echo "MPI settings: $(env | grep '^OMPI_MCA_' | sort | tr '\n' ' ')"
echo "Compiler: $(gcc --version | sed -n '1p')"
echo "MPI: $(mpirun --version | sed -n '1p')"
node_state start
job_resources || echo "Some allocation details were unavailable"
bash tools/capture_env.sh > "results/raw/e7-e9/env_${SLURM_JOB_ID}.txt" || echo "Environment capture failed; continuing"

launch=(srun --kill-on-bad-exit=1 --cpu-bind=verbose,cores)
args=(--nx 8192 --ny 8192 --steps 400 --seed 42 --ignitions 16 --decomp "$decomp")
for mode in 0 1; do
    cmd=("${launch[@]}" "$bin" "${args[@]}" --overlap "$mode" --verify-only)
    printf 'command:'; printf ' %q' "${cmd[@]}"; printf '\n'
    out=$("${cmd[@]}")
    printf '%s\n' "$out"
    if [[ $(printf '%s\n' "$out" | sed -n 's/^VERIFY checksum=//p') != "$reference" ]]; then
        echo "CHECKSUM MISMATCH in untimed verification for overlap=$mode" >&2
        exit 1
    fi
done
echo "VERIFIED checksum=$reference"
if [[ "$verify_only" == 1 ]]; then
    exit 0
fi

# Profile rank 0 in separate jobs. Probe counters on its allocated CPU first.
prefix=()
if [[ "$profile" == perf ]]; then
    events=task-clock,cycles,instructions,cache-misses
    if ! srun --nodes=1 --ntasks=1 --cpus-per-task=1 --cpu-bind=cores \
        perf stat -e "$events" -- true; then
        echo "perf unavailable or hardware counters denied; use E7 application timers for E9" >&2
        exit 1
    fi
    prefix=(bash -c 'if [[ $SLURM_PROCID == 0 ]]; then
                        exec perf stat -e "$1" -- "${@:2}"
                    fi
                    exec "${@:2}"' perf-rank "$events")
fi

first=$(( (rep + 1) % 2 ))
for mode in "$first" "$((1 - first))"; do
    cmd=("${launch[@]}" "${prefix[@]}" "$bin" "${args[@]}" --overlap "$mode")
    printf 'command:'; printf ' %q' "${cmd[@]}"; printf '\n'
    out=$("${cmd[@]}")
    printf '%s\n' "$out"
    result=$(printf '%s\n' "$out" | sed -n '/^RESULT /p')
    if [[ "$result" == *$'\n'* || " $result " != *" checksum=$reference "* ||
          " $result " != *" commit=$rev "* || " $result " != *" overlap=$mode "* ||
          " $result " != *" ranks=$SLURM_NTASKS threads=$OMP_NUM_THREADS "* ||
          " $result " != *" nodes=$SLURM_JOB_NUM_NODES "* ]]; then
        echo "Timed checksum, revision or placement mismatch for overlap=$mode" >&2
        exit 1
    fi
done
node_state end
echo 'PAIR COMPLETE'
