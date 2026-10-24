# src

C sources for the simulator. Planned layout:

    main.c            setup, time loop, final report
    params.c/.h       command line options
    landscape.c       synthetic landscape and file reader
    decomp.c          process grid and neighbours (MPI)
    halo.c            halo exchange
    rules.h, rng.h    the cell rule and the hash based random number
    step_serial.c, step_omp.c, step_cuda.cu, step_acc.c
    output.c          checksum, counts, snapshots
    timers.c, report.c
    bench/            small hardware benchmarks (ping-pong)

See docs/architecture.pdf for the reasoning behind this split.
