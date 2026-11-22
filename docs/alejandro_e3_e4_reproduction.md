# Reproducing E3 and E4

The [results section](alejandro_section5_results.md) and [slide](alejandro_slide3.md)
use the 30 final logs in [results/raw](../results/raw). Those logs record
simulator commit `ce2e211` on the HPC cluster. That revision was absent from
the local repository during analysis. Fetching from GitHub recovered it as the
tip of `origin/main`. For an exact simulator rerun, build from `ce2e211` and
use the recorded cluster configuration. The transferred logs are sufficient
to regenerate the figures and tables.

## Regenerate the report figures and tables

Install the Python dependencies listed in [env/requirements.txt](../env/requirements.txt).
From the repository root, choose a new output directory and run:

```bash
python3 tools/plot_phase3a.py results/raw results/phase3a_report --report
```

The report option emits only final 32-core E3 and E4 data. It writes one summary
and one per-run CSV plus a PNG and PDF per experiment. The checked-in summary
and per-run CSVs have the added suffix `_final` and `_final_runs`, respectively.
[The report draft](alejandro_section5_results.md) gives the figure captions.

## Repeat the benchmarks

On the cluster, build on a compute node using [build.sbatch](../slurm/build.sbatch)
and check that both serial and MPI builds come from the intended revision.
Use [mpi_check.sbatch](../slurm/mpi_check.sbatch) to confirm the launcher on
`haskell` and on `haskell,julia`. The recorded benchmarks used Slurm core
binding and `OMP_PROC_BIND=close` with `OMP_PLACES=cores`. The logs record MPI
transport settings. Job 34260 used the default transport, and the other final
runs used `ob1` with `self,vader,tcp`.

The planner prints the E3 or E4 commands by default:

```bash
bash slurm/submit_phase3a.sh e3
bash slurm/submit_phase3a.sh e4
```

The planner skips configurations with verified logs, recorded submission IDs,
or existing Slurm comments during preflight and submission. For an intentional
rerun, use a separate run directory and coordinate with the cluster account
owner before reusing any Slurm comment. Pass the one- and two-node launcher logs
via `--probe-1` and `--probe-2` when using `--preflight` or `--submit`.
The [hybrid job](../slurm/hybrid.sbatch) compares each E4 grid against the serial
binary before accepting its timed MPI result.
