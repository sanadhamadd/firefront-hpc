# SciTech cluster

From `env/cluster_info.txt` (`tools/cluster_info.sh` on the login node, 2026-10-25) and
`results/raw/cluster_info_node_24873.out` (`slurm/cluster_info_node.sbatch`, compute node haskell).

## Compute node (haskell)

| | |
|---|---|
| CPU | 2 × AMD EPYC 9755 (Zen 5), up to 4.1 GHz |
| Sockets | 2 |
| Cores per socket | 128 |
| Threads per core | 2 (SMT on) |
| Physical cores per node | 256 |
| Hardware threads per node | 512 (the "CPUs" Slurm counts) |
| NUMA domains | 2, one per socket: node 0 = CPUs 0–127 and 256–383, node 1 = CPUs 128–255 and 384–511; distance 10 local / 32 remote |
| Memory | 193 GB on NUMA node 0 + 257 GB on NUMA node 1 (Slurm: 406528 MB usable) |
| Caches | L1d 48 KB and L2 1 MB per core; L3 32 MB per 8-core CCD, 32 CCDs, 1 GB per node |
| Vector units | AVX2 and AVX-512 |

Only haskell was checked. The other node, julia, is listed with the same 512 CPUs but 515002 MB of memory; run `sbatch -w julia slurm/cluster_info_node.sbatch` to see whether its CPU is the same.

`nvidia-smi` printed "No devices were found" on haskell because the job asked for no GPU; Slurm only shows a job the GPUs it requested.

## Slurm

| | |
|---|---|
| Nodes | haskell, julia (both are in every partition) |
| Partitions | `cpu` (default, max 7 days), `gpu` (max 3 days), `interactive` (max 8 h) |
| GPUs | `gpu:rtx6000ada:2` on one node, `gpu:rtx6000bb:1` on the other |
| Account / QOS | `hpcclass` / `student`, the defaults, so the job scripts do not set them |
| Allocation | `SelectTypeParameters=CR_CORE_MEMORY`: whole cores and memory are handed out; a core has 2 hardware threads and Slurm counts each as a CPU |
| Sharing | `OverSubscribe=FORCE:2` on all partitions: each core can be given to up to 2 jobs at the same time, and users cannot turn this off (`--exclusive` does not prevent it) |
| Preemption | `PreemptType=preempt/qos`, `PreemptMode=REQUEUE` (no gang scheduling, so jobs that share cores run at the same time) |
| MPI launch | `srun --mpi=list`: none, pmi2, cray_shasta, pmix (pmix_v5) |

## Limits of the student QOS

| | |
|---|---|
| CPUs per user | `MaxTRESPU cpu=64`: at most 64 CPUs at a time, i.e. **32 physical cores** (2 hardware threads each) |
| Running jobs per user | `MaxJobsPU=4` |
| Queued jobs per user | `MaxSubmitPU=8` (running + pending) |
| Wall time | no QOS limit, so the partition limit applies (we keep every job at 10 min) |

What this means for us:
- One OpenMP job can use at most 32 cores. E2 and STREAM ask for `--cpus-per-task=64 --hint=multithread` (32 whole cores with both hardware threads) and run their whole thread series inside one job.
- STREAM measures the memory bandwidth available to 32 cores, not to a whole 256-core node.
- MPI runs on 2 nodes may use at most 64 CPUs **in total**, e.g. 2 nodes × 16 cores (with `--hint=nomultithread`).
- At most 8 jobs can be queued, so a series is submitted in parts (e.g. build + E1 + E2 = 7 jobs, STREAM afterwards).
- Build, E1, E2 and STREAM run on haskell only (`--nodelist=haskell`): same CPU for the `-march=native` build and all timed runs, and the node this file describes. E2 and STREAM also ask for one socket, so their 32 cores share one NUMA domain.
- With 32 cores, the 8192² grid (0.67 GB) is far larger than the ~128 MB of L3 those cores reach (4 CCDs × 32 MB), so E2 runs from memory.

## Login node (rust)

A small virtual machine: 4 vCPUs ("Common KVM processor", no AVX), 32 GB. It is **not** the same CPU as the compute nodes: a binary built there with `-march=native` targets that virtual CPU, not Zen 5.

## Modules

See `env/modules.txt`. Chosen toolchain: GCC 13.2.0 (newest GCC on the cluster) with the OpenMPI built with it.
There is no LIKWID module; PAPI (`PAPI/7.1.0-GCCcore-13.2.0`) is available for hardware counters.

**Note for the MPI phase: two different MPIs.** Without any module loaded, the compute node already has an `mpirun` from Open MPI **5.0.7** in the system path (seen in the environment snapshots of our jobs). Our chosen module is **OpenMPI/4.1.6-GCC-13.2.0**. A program must be built and started with the same MPI, otherwise it fails at start-up or behaves oddly. So:
- `slurm/build.sbatch` must `module load OpenMPI/4.1.6-GCC-13.2.0` before the MPI target is built (today it only loads GCC, because there is no MPI target yet);
- `slurm/hybrid.sbatch` loads the same module before `srun` (it does);
- both should log `which mpicc mpirun` and `mpirun --version`, and we check that they point into the module, not to the system copy.
