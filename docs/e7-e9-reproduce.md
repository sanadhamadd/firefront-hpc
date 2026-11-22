# E7 overlap and E9 profiling

Use the team’s current experiment numbers. Commit the reviewed source and scripts on
`khadija/e7-overlap-profiling` and check out that same commit on SciTech. From the
repository root on the login node, submit the build to a compute node:

```bash
mkdir -p results/raw/e7-e9
sbatch --parsable slurm/build.sbatch
```

Confirm that the build job completed successfully with `sacct -j BUILD_JOB_ID`
and review `results/raw/build_BUILD_JOB_ID.out` for both the ordinary and MPI
checks. The build log records GCC, Open MPI and the actual compilation flags.
Use the same binary for all compared jobs. The E7 job checks the binary’s
recorded commit against the checkout, so rebuild after switching revisions.
The reference run uses 8192 × 8192
cells, 400 steps, 16 ignitions, seed 42, no snapshot and all other model defaults.

Run an untimed two-node correctness check on the production workload:

```bash
sbatch --parsable --nodes=2 --ntasks=32 --ntasks-per-node=16 \
  --nodelist=haskell,julia --output=results/raw/e7-e9/e7_verify_%j.out \
  --export=ALL,DECOMP=blocks,REP=1,PROFILE=none,VERIFY_ONLY=1 \
  slurm/e7_overlap.sbatch
```

The job first executes both modes with `--verify-only`. Each must print
`VERIFY checksum=0xb8683c550fa95bd6` before the job launches timed steps.
Each timed result must independently reproduce the checksum and the checked-out
commit. A job with an error or mismatch cannot emit `PAIR COMPLETE`.

Confirm `COMPLETED` in `sacct` and inspect the two `VERIFY` lines and final
`VERIFIED` line. When those pass, run the five-pair sweep:

```bash
bash slurm/submit_e7.sh
```

The sweep uses 4, 8, 16 and 32 ranks on haskell and 8, 16 and 32 ranks across
haskell and julia, split evenly. It uses one thread per rank, one paired
repetition per job, an 8 GB memory request per node, a ten-minute time limit
and the existing singleton dependency and queue limits. Odd repetitions run
blocking first and even repetitions run overlap first. Slurm logs the binding
for both steps. Check the actual placement and note concurrent jobs before
interpreting unusual results. Keep the tested `ob1` transport and its
`self,vader,tcp` BTLs throughout. For decomposition sensitivity, use
`DECOMP=strips bash slurm/submit_e7.sh` with the same build and placement.

## E9 profiling

Use E7 application timers as the primary, all-rank profile. Optionally submit
separate jobs to collect rank 0 hardware counters with `perf stat`:

```bash
for ranks in 1 32; do
  sbatch --parsable --nodes=1 --ntasks="$ranks" --ntasks-per-node="$ranks" \
    --nodelist=haskell --output=results/raw/e7-e9/e9_perf_%j.out \
    --export=ALL,DECOMP=blocks,REP=1,PROFILE=perf,VERIFY_ONLY=0 slurm/e7_overlap.sbatch
done
sbatch --parsable --nodes=2 --ntasks=32 --ntasks-per-node=16 \
  --nodelist=haskell,julia --output=results/raw/e7-e9/e9_perf_%j.out \
  --export=ALL,DECOMP=blocks,REP=1,PROFILE=perf,VERIFY_ONLY=0 slurm/e7_overlap.sbatch
sacct -j JOB_ID --format=JobID,State,ExitCode,Elapsed,AllocCPUS,NodeList,MaxRSS
```

The counter probe can fail if `perf` or its events are unavailable on the
allocated node. Retain that diagnostic. Counters cover the whole rank 0
process, including setup and MPI, so they cannot establish kernel memory
bandwidth. The benchmark CSV excludes profiler jobs. Record Slurm job states
using `sacct`. Keep only vetted, team-safe logs and environment snapshots.
The shared node logger anonymizes users. Inspect logs before adding them to Git.

## Analysis and interpretation

On a machine with the packages in `env/requirements.txt`, select one complete
log per configuration and repetition. Then run from the repository root:

```bash
python tools/analyze_e7.py results/raw/e7-e9
```

This writes `e7_runs.csv`, `e7_summary.csv` and four figures in PNG and PDF.
Use `--csv-only` to skip plotting. Runtime is the maximum rank time over the
390 timed steps. Each phase is accumulated per rank before taking its rank
maximum. The maxima can come from different ranks and cannot be added to
reconstruct the run. Blocking `t_halo` is time inside the full exchange.
Overlap `t_halo` is the exposed MPI time (posting plus waiting).
`t_wait` measures only completion calls, which can perform MPI progress
as well as wait. `t_compute` includes OpenMP worksharing overhead.
`imbalance` is maximum compute time divided by the mean rank compute time.

Use median wall time with min–max across pairs, optimization speedup
`median(blocking) / median(overlap)`, and runtime reduction
`100 × (1 − median(overlap) / median(blocking))`. For context, the E5
strong-scaling speedup uses the 81.95 s serial E1 median, and its efficiency
divides that speedup by physical cores. The E7 ratio compares modes at a
fixed allocation.
