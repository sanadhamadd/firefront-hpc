# Build the serial and OpenMP versions. MPI and GPU targets will be added with their sources.
#
#   make serial     ->  build/firefront_serial
#   make omp        ->  build/firefront_omp      (needs a compiler with OpenMP, e.g. gcc on the cluster)
#   make mpi        ->  build/firefront_mpi      (MPI + OpenMP; on a Mac without OpenMP: make mpi MPI_OMP=)
#   make stream     ->  build/stream             (STREAM triad memory bandwidth, also needs OpenMP)
#   make test       ->  build and run the tests
#   make test-mpi   ->  MPI checks with several rank counts (needs mpicc and mpirun; on a Mac: make test-mpi MPI_OMP=)
#   make clean

ifeq ($(origin CC),default)
CC = gcc
endif
NATIVE  ?= -march=native
CFLAGS  ?= -O3 $(NATIVE)
CFLAGS  += -std=c11 -Wall -Wextra -ffp-contract=off -D_POSIX_C_SOURCE=200809L
COMMIT  := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
DEFS     = -DGIT_COMMIT=\"$(COMMIT)\"
LIBS     = -lm
MPICC   ?= mpicc
MPI_OMP ?= -fopenmp

CORE = src/sim.c src/params.c src/landscape.c src/decomp.c src/halo.c
HDRS = $(wildcard src/*.h)

.PHONY: all serial omp mpi stream test test-mpi clean
all: serial

serial: build/firefront_serial
omp:    build/firefront_omp
mpi:    build/firefront_mpi
stream: build/stream

build/firefront_serial: src/main.c $(CORE) $(HDRS)
	@mkdir -p build
	$(CC) $(CFLAGS) $(DEFS) -DVARIANT=\"serial\" -o $@ src/main.c $(CORE) $(LIBS)

build/firefront_omp: src/main.c $(CORE) $(HDRS)
	@mkdir -p build
	$(CC) $(CFLAGS) -fopenmp $(DEFS) -DVARIANT=\"omp\" -o $@ src/main.c $(CORE) $(LIBS)

build/firefront_mpi: src/main.c $(CORE) $(HDRS)
	@mkdir -p build
	$(MPICC) $(CFLAGS) $(MPI_OMP) -DUSE_MPI $(DEFS) -DVARIANT=\"mpi\" -o $@ src/main.c $(CORE) $(LIBS)

build/stream: src/bench/stream.c src/timers.h
	@mkdir -p build
	$(CC) $(CFLAGS) -fopenmp $(DEFS) -o $@ src/bench/stream.c

build/test_model: tests/test_model.c $(CORE) $(HDRS)
	@mkdir -p build
	$(CC) $(CFLAGS) $(DEFS) -Isrc -o $@ tests/test_model.c $(CORE) $(LIBS)

build/test_decomp: tests/test_decomp.c src/decomp.c src/decomp.h
	@mkdir -p build
	$(CC) $(CFLAGS) -Isrc -o $@ tests/test_decomp.c src/decomp.c

build/test_decomp_mpi: tests/test_decomp_mpi.c src/decomp.c src/decomp.h
	@mkdir -p build
	$(MPICC) $(CFLAGS) -DUSE_MPI -Isrc -o $@ tests/test_decomp_mpi.c src/decomp.c

test: build/test_model build/test_decomp serial
	./build/test_model
	./build/test_decomp
	bash tests/run_all.sh

build/test_halo_mpi: tests/test_halo_mpi.c src/decomp.c src/halo.c src/decomp.h src/halo.h src/rng.h
	@mkdir -p build
	$(MPICC) $(CFLAGS) -DUSE_MPI -Isrc -o $@ tests/test_halo_mpi.c src/decomp.c src/halo.c

test-mpi: build/test_decomp_mpi build/test_halo_mpi mpi serial
	bash tests/run_mpi.sh

clean:
	rm -rf build
