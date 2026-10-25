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
| Account / QOS | `hpcclass` / `student` |
| Sharing | `OverSubscribe=FORCE:2` on all partitions: each CPU can be given to up to 2 jobs at the same time, and users cannot turn this off |
| Preemption | `PreemptMode=REQUEUE` (no gang scheduling, so jobs that share CPUs run at the same time) |
| MPI launch | `srun --mpi=list`: none, pmi2, cray_shasta, pmix (pmix_v5) |

## Login node (rust)

A small virtual machine: 4 vCPUs ("Common KVM processor", no AVX), 32 GB. It is **not** the same CPU as the compute nodes: a binary built there with `-march=native` targets that virtual CPU, not Zen 5.

## Modules

See `env/modules.txt`. Chosen toolchain: GCC 13.2.0 (newest GCC on the cluster) with the OpenMPI built with it.
There is no LIKWID module; PAPI (`PAPI/7.1.0-GCCcore-13.2.0`) is available for hardware counters.
