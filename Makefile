# Build the serial, OpenMP, MPI and GPU versions.
#
#   make serial     ->  build/firefront_serial
#   make omp        ->  build/firefront_omp      (needs a compiler with OpenMP, e.g. gcc on the cluster)
#   make mpi        ->  build/firefront_mpi      (MPI + OpenMP; on a Mac without OpenMP: make mpi MPI_OMP=)
#   make stream     ->  build/stream             (STREAM triad memory bandwidth, also needs OpenMP)
#   make cuda       ->  build/firefront_cuda     (needs nvcc; host code is -march=znver4, see below)
#   make acc        ->  build/firefront_acc      (needs nvc, OpenACC on the GPU)
#   make acc-mc     ->  build/firefront_acc_mc   (OpenACC multicore, the fallback if the GPU queue is blocked)
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

CORE = src/sim.c src/params.c src/landscape.c src/decomp.c src/halo.c src/ignite.c src/rules_build.c
HDRS = $(wildcard src/*.h)

# Host objects of the GPU binaries. znver4 is what GCC 13.2 -march=native selects on
# haskell (REPRODUCE.md). The GPU may sit on the other node, so do not use -march=native
# here: a znver4 binary still runs on both Zen 4 and Zen 5, and it matches the serial
# checksums, which were produced on haskell.
NVCC ?= nvcc
NVC ?= nvc
CUDA_ARCH ?= sm_89
CUDA_HOST_MARCH ?= -march=znver4
CUDA_CFLAGS = -O3 $(CUDA_HOST_MARCH) -std=c11 -Wall -Wextra -ffp-contract=off -D_POSIX_C_SOURCE=200809L
ACC_GPU_FLAGS = -acc=gpu -gpu=cc89 -Mnofma -O3 -Minfo=accel
ACC_MC_FLAGS = -acc=multicore -Mnofma -O3 -Minfo=accel

.PHONY: all serial omp mpi stream cuda acc acc-mc test test-mpi clean
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

# GPU host objects. main.c is the only one that differs between CUDA and OpenACC
# (USE_CUDA / USE_ACC); the others are the serial sources compiled for znver4.
build/gpu_params.o: src/params.c $(HDRS)
	@mkdir -p build
	$(CC) $(CUDA_CFLAGS) -c -o $@ src/params.c

build/gpu_landscape.o: src/landscape.c $(HDRS)
	@mkdir -p build
	$(CC) $(CUDA_CFLAGS) -c -o $@ src/landscape.c

build/gpu_decomp.o: src/decomp.c $(HDRS)
	@mkdir -p build
	$(CC) $(CUDA_CFLAGS) -c -o $@ src/decomp.c

build/gpu_ignite.o: src/ignite.c $(HDRS)
	@mkdir -p build
	$(CC) $(CUDA_CFLAGS) -c -o $@ src/ignite.c

build/gpu_rules.o: src/rules_build.c $(HDRS)
	@mkdir -p build
	$(CC) $(CUDA_CFLAGS) -c -o $@ src/rules_build.c

GPU_COMMON = build/gpu_params.o build/gpu_landscape.o build/gpu_decomp.o build/gpu_ignite.o build/gpu_rules.o

build/gpu_main_cuda.o: src/main.c $(HDRS)
	@mkdir -p build
	$(CC) $(CUDA_CFLAGS) $(DEFS) -DUSE_CUDA -DVARIANT=\"cuda\" -c -o $@ src/main.c

build/step_cuda.o: src/step_cuda.cu $(HDRS)
	@mkdir -p build
	$(NVCC) -ccbin $(CC) -O3 --fmad=false -Xptxas --fmad=false -arch=$(CUDA_ARCH) -std=c++17 -DUSE_CUDA \
	  -Xcompiler -O3 -Xcompiler -ffp-contract=off -Xcompiler $(CUDA_HOST_MARCH) \
	  -c -o $@ src/step_cuda.cu

build/firefront_cuda: build/gpu_main_cuda.o build/step_cuda.o $(GPU_COMMON)
	$(NVCC) -ccbin $(CC) -arch=$(CUDA_ARCH) -o $@ $^ -lm

cuda: build/firefront_cuda

build/gpu_main_acc.o: src/main.c $(HDRS)
	@mkdir -p build
	$(CC) $(CUDA_CFLAGS) $(DEFS) -DUSE_ACC -DVARIANT=\"acc\" -c -o $@ src/main.c

build/gpu_main_acc_mc.o: src/main.c $(HDRS)
	@mkdir -p build
	$(CC) $(CUDA_CFLAGS) $(DEFS) -DUSE_ACC -DVARIANT=\"accmc\" -c -o $@ src/main.c

build/step_acc.o: src/step_acc.c $(HDRS)
	@mkdir -p build
	$(NVC) $(ACC_GPU_FLAGS) -DUSE_ACC -c -o $@ src/step_acc.c

build/step_acc_mc.o: src/step_acc.c $(HDRS)
	@mkdir -p build
	$(NVC) $(ACC_MC_FLAGS) -DUSE_ACC -c -o $@ src/step_acc.c

build/firefront_acc: build/gpu_main_acc.o build/step_acc.o $(GPU_COMMON)
	$(NVC) $(ACC_GPU_FLAGS) -o $@ $^ -lm

build/firefront_acc_mc: build/gpu_main_acc_mc.o build/step_acc_mc.o $(GPU_COMMON)
	$(NVC) $(ACC_MC_FLAGS) -o $@ $^ -lm

acc: build/firefront_acc
acc-mc: build/firefront_acc_mc

clean:
	rm -rf build
