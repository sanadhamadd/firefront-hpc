# PR draft for Sanad

**Title** · Add nonblocking MPI halo overlap and paired SciTech experiments

Add `--overlap 1` to the existing MPI simulator. Post row messages, update
the interior, finish row requests, then exchange columns with corner cells
before updating the boundary. Keep `--overlap 0` as the blocking control and
append optional phase timings to the existing RESULT fields.

Add serial/MPI checksum comparisons, direct halo tests, uneven and narrow
domains, hybrid execution and snapshot comparisons. Preserve the existing
1024² reference. The dedicated Slurm job verifies both modes untimed against
the 8192² reference before collecting each paired measurement.

**Verification** · Windows MSYS2 `make test` passed, including serial
reference validation and OpenMP checksum comparisons at 1, 2, 4 and 8 threads.
Ubuntu WSL with Open MPI 4.1.6 passed `make test-mpi` at 1, 2, 3, 4, 6
and 8 ranks for both modes, including direct edge and corner checks,
hybrid checks and snapshot comparisons. The E7 analysis unit tests passed.
SciTech checksum, paired jobs and E9 counter availability remain pending.

**For Alicia** · Incorporate [E7/E9 reproduction](e7-e9-reproduce.md) and
[report sections 6 and 7](e7-e9-report-draft.md) once the figures are available.

**For Alejandro** · E7 uses the same 8192² workload as E1/E5 and the same
`ob1`/TCP fallback for multi-node jobs as the hybrid workflow. The shared
comparison points are 32 ranks × 1 thread on one node and 16 ranks per node
across two nodes. Label the E7 blocking/overlap ratio separately from E3
scaling efficiency. E7 changes no hybrid job defaults.

**Suggested commits**

- `Add optional two-phase MPI halo overlap and correctness tests`
- `Prepare paired E7 Slurm benchmarks and E9 profiling analysis`
- `Draft bottleneck and optimization report sections and slide 4`
