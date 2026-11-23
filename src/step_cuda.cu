/* CUDA port of one step. The whole grid stays on the device: one kernel per step,
   two state buffers, fuel and elevation uploaded once. The cell rule is ff_cell_update
   (src/update.h), the same function the CPU loops call. Compile with nvcc --fmad=false
   so the probability product is not contracted, matching -ffp-contract=off. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <cuda_runtime.h>

extern "C" {
#include "landscape.h"
#include "sim.h"
#include "timers.h"
#include "update.h"
}

__constant__ Rules c_rules;
__constant__ int c_offset[8];

__global__ void step_kernel(
    const uint8_t *old, uint8_t *new_,
    const float *fuel, const float *elev,
    int nx, int ny, int stride,
    uint64_t seed, uint64_t step)
{
    int c = blockIdx.x * blockDim.x + threadIdx.x;
    int r = blockIdx.y * blockDim.y + threadIdx.y;
    if (c >= nx || r >= ny)
        return;
    int i = (r + 1) * stride + (c + 1);
    uint64_t cell = (uint64_t)r * (uint64_t)nx + (uint64_t)c;
    ff_cell_update(&c_rules, fuel, elev, old, new_, c_offset,
                   c_rules.burn_steps, i, seed, cell, step);
}

/* One thread per row, then one atomic per row. Used only for the progress counts,
   not for the checksum (that is the host hash of the downloaded state). */
__global__ void count_kernel(
    const uint8_t *state, int nx, int ny, int stride, int burn_steps,
    unsigned long long *burning, unsigned long long *burnt)
{
    int r = blockIdx.x * blockDim.x + threadIdx.x;
    if (r >= ny)
        return;
    unsigned long long nb = 0, nt = 0;
    const uint8_t *row = state + (size_t)(r + 1) * (size_t)stride + 1;
    for (int c = 0; c < nx; c++) {
        uint8_t st = row[c];
        if (st == STATE_BURNT)
            nt++;
        else if (is_burning(st, burn_steps))
            nb++;
    }
    if (nb)
        atomicAdd(burning, nb);
    if (nt)
        atomicAdd(burnt, nt);
}

struct Sim {
    Params p;
    Rules rules;
    int stride;
    int step;
    size_t n;
    double t_halo, t_compute;
    double t_h2d, t_d2h, t_kernel;
    int kernel_ready;
    int host_valid;
    int events_ready;
    float *h_fuel, *h_elev;
    uint8_t *h_state;
    float *d_fuel, *d_elev;
    uint8_t *d_old, *d_new;
    unsigned long long *d_counts;
    cudaEvent_t h2d_a, h2d_b, d2h_a, d2h_b;
    cudaEvent_t *ev_beg, *ev_end;
    int n_ev, cap_ev;
};

static int cuda_fail(cudaError_t e, const char *what)
{
    if (e == cudaSuccess)
        return 0;
    fprintf(stderr, "CUDA error in %s: %s\n", what, cudaGetErrorString(e));
    return 1;
}

static void free_step_events(Sim *s)
{
    for (int i = 0; i < s->n_ev; i++) {
        cudaEventDestroy(s->ev_beg[i]);
        cudaEventDestroy(s->ev_end[i]);
    }
    s->n_ev = 0;
}

static int grow_events(Sim *s)
{
    if (s->n_ev < s->cap_ev)
        return 1;
    int cap = s->cap_ev ? s->cap_ev * 2 : 64;
    cudaEvent_t *b = (cudaEvent_t *)realloc(s->ev_beg, (size_t)cap * sizeof *b);
    if (!b)
        return 0;
    s->ev_beg = b;
    cudaEvent_t *e = (cudaEvent_t *)realloc(s->ev_end, (size_t)cap * sizeof *e);
    if (!e)
        return 0;
    s->ev_end = e;
    s->cap_ev = cap;
    return 1;
}

static void finish_kernel_timer(Sim *s)
{
    if (s->kernel_ready)
        return;
    double sec = 0.0;
    if (s->n_ev > 0) {
        cudaEventSynchronize(s->ev_end[s->n_ev - 1]);
        for (int i = 0; i < s->n_ev; i++) {
            float ms = 0.0f;
            cudaEventElapsedTime(&ms, s->ev_beg[i], s->ev_end[i]);
            sec += (double)ms / 1000.0;
        }
    }
    s->t_kernel = sec;
    s->t_compute = sec;
    s->kernel_ready = 1;
}

static int pull_state(Sim *s)
{
    if (s->host_valid)
        return 1;
    finish_kernel_timer(s);
    if (cuda_fail(cudaEventRecord(s->d2h_a), "record download start"))
        return 0;
    if (cuda_fail(cudaMemcpy(s->h_state, s->d_old, s->n, cudaMemcpyDeviceToHost), "download state"))
        return 0;
    if (cuda_fail(cudaEventRecord(s->d2h_b), "record download end"))
        return 0;
    if (cuda_fail(cudaEventSynchronize(s->d2h_b), "wait for download"))
        return 0;
    float ms = 0.0f;
    cudaEventElapsedTime(&ms, s->d2h_a, s->d2h_b);
    s->t_d2h = (double)ms / 1000.0;
    s->host_valid = 1;
    return 1;
}

static void ignite_patch(Sim *s, int ix, int iy)
{
    for (int dy = 0; dy < 3; dy++) {
        for (int dx = 0; dx < 3; dx++) {
            int x = ix + dx, y = iy + dy;
            if (x >= s->p.nx || y >= s->p.ny)
                continue;
            s->h_state[(size_t)(y + 1) * (size_t)s->stride + (size_t)(x + 1)] = 1;
        }
    }
}

static uint8_t grey_of(const Sim *s, int i)
{
    uint8_t st = s->h_state[i];
    if (st == STATE_BURNT)  return 25;
    if (st >= 1)            return 110;
    if (s->h_fuel[i] <= 0.0f) return 150;
    return 215;
}

static long long count_on_device(Sim *s, int which)
{
    unsigned long long zero[2] = { 0, 0 };
    if (cuda_fail(cudaMemcpy(s->d_counts, zero, sizeof zero, cudaMemcpyHostToDevice), "zero counts"))
        return -1;
    int threads = 256;
    int blocks = (s->p.ny + threads - 1) / threads;
    count_kernel<<<blocks, threads>>>(s->d_old, s->p.nx, s->p.ny, s->stride,
                                      s->rules.burn_steps, s->d_counts, s->d_counts + 1);
    unsigned long long host[2];
    if (cuda_fail(cudaMemcpy(host, s->d_counts, sizeof host, cudaMemcpyDeviceToHost), "read counts"))
        return -1;
    if (cuda_fail(cudaGetLastError(), "count kernel"))
        return -1;
    return (long long)host[which];
}

extern "C" Sim *sim_create(const Params *p)
{
    if (p->skip_tiles > 0) {
        fprintf(stderr, "--skip-tiles is a CPU-only optimisation (E8); the GPU build does not implement it\n");
        return NULL;
    }
    if ((size_t)(p->nx + 2) * (size_t)(p->ny + 2) > (size_t)2147483647) {
        fprintf(stderr, "grid is too large for the GPU kernel's 32-bit cell index\n");
        return NULL;
    }

    Sim *s = (Sim *)calloc(1, sizeof *s);
    if (!s)
        return NULL;
    s->p = *p;
    s->stride = p->nx + 2;
    s->n = (size_t)s->stride * (size_t)(p->ny + 2);
    rules_build(&s->rules, p);

    s->h_fuel = (float *)malloc(s->n * sizeof(float));
    s->h_elev = (float *)malloc(s->n * sizeof(float));
    s->h_state = (uint8_t *)calloc(s->n, 1);
    if (!s->h_fuel || !s->h_elev || !s->h_state) {
        sim_free(s);
        return NULL;
    }
    landscape_fill(s->h_fuel, s->h_elev, p->nx, p->ny, 0, 0, p);
    if (p->ignitions == 1) {
        int ix = (p->ignite_x >= 0) ? p->ignite_x : p->nx / 6;
        int iy = (p->ignite_y >= 0) ? p->ignite_y : p->ny / 2;
        ignite_patch(s, ix, iy);
    } else {
        int x, y;
        for (int k = 0; k < p->ignitions; k++) {
            sim_ignition_place(p, k, &x, &y);
            ignite_patch(s, x, y);
        }
    }

    if (cuda_fail(cudaMalloc((void **)&s->d_fuel, s->n * sizeof(float)), "allocate fuel") ||
        cuda_fail(cudaMalloc((void **)&s->d_elev, s->n * sizeof(float)), "allocate elevation") ||
        cuda_fail(cudaMalloc((void **)&s->d_old, s->n), "allocate state") ||
        cuda_fail(cudaMalloc((void **)&s->d_new, s->n), "allocate next state") ||
        cuda_fail(cudaMalloc((void **)&s->d_counts, 2 * sizeof(unsigned long long)), "allocate counts") ||
        cuda_fail(cudaEventCreate(&s->h2d_a), "create upload event") ||
        cuda_fail(cudaEventCreate(&s->h2d_b), "create upload event") ||
        cuda_fail(cudaEventCreate(&s->d2h_a), "create download event") ||
        cuda_fail(cudaEventCreate(&s->d2h_b), "create download event")) {
        sim_free(s);
        return NULL;
    }
    s->events_ready = 1;

    int offset[8];
    for (int d = 0; d < 8; d++)
        offset[d] = NB_DR[d] * s->stride + NB_DC[d];
    if (cuda_fail(cudaMemcpyToSymbol(c_rules, &s->rules, sizeof(Rules)), "copy rule tables") ||
        cuda_fail(cudaMemcpyToSymbol(c_offset, offset, sizeof offset), "copy neighbour offsets") ||
        cuda_fail(cudaMemset(s->d_new, 0, s->n), "clear next state") ||
        cuda_fail(cudaEventRecord(s->h2d_a), "record upload start") ||
        cuda_fail(cudaMemcpyAsync(s->d_fuel, s->h_fuel, s->n * sizeof(float), cudaMemcpyHostToDevice), "upload fuel") ||
        cuda_fail(cudaMemcpyAsync(s->d_elev, s->h_elev, s->n * sizeof(float), cudaMemcpyHostToDevice), "upload elevation") ||
        cuda_fail(cudaMemcpyAsync(s->d_old, s->h_state, s->n, cudaMemcpyHostToDevice), "upload state") ||
        cuda_fail(cudaEventRecord(s->h2d_b), "record upload end") ||
        cuda_fail(cudaEventSynchronize(s->h2d_b), "wait for upload")) {
        sim_free(s);
        return NULL;
    }
    float ms = 0.0f;
    cudaEventElapsedTime(&ms, s->h2d_a, s->h2d_b);
    s->t_h2d = (double)ms / 1000.0;
    s->host_valid = 1;   /* h_state still holds the initial grid; the first step clears this */
    return s;
}

extern "C" void sim_free(Sim *s)
{
    if (!s)
        return;
    cudaDeviceSynchronize();
    free_step_events(s);
    free(s->ev_beg);
    free(s->ev_end);
    if (s->events_ready) {
        cudaEventDestroy(s->h2d_a);
        cudaEventDestroy(s->h2d_b);
        cudaEventDestroy(s->d2h_a);
        cudaEventDestroy(s->d2h_b);
    }
    if (s->d_fuel) cudaFree(s->d_fuel);
    if (s->d_elev) cudaFree(s->d_elev);
    if (s->d_old) cudaFree(s->d_old);
    if (s->d_new) cudaFree(s->d_new);
    if (s->d_counts) cudaFree(s->d_counts);
    free(s->h_fuel);
    free(s->h_elev);
    free(s->h_state);
    free(s);
}

extern "C" void sim_step(Sim *s)
{
    s->step++;
    if (!grow_events(s)) {
        fprintf(stderr, "out of memory recording the step timer\n");
        return;
    }
    int n = s->n_ev;
    cudaEventCreate(&s->ev_beg[n]);
    cudaEventCreate(&s->ev_end[n]);
    cudaEventRecord(s->ev_beg[n]);

    dim3 block(16, 16);
    dim3 grid((s->p.nx + block.x - 1) / block.x, (s->p.ny + block.y - 1) / block.y);
    step_kernel<<<grid, block>>>(s->d_old, s->d_new, s->d_fuel, s->d_elev,
                                 s->p.nx, s->p.ny, s->stride, s->p.seed, (uint64_t)s->step);
    cudaEventRecord(s->ev_end[n]);
    s->n_ev++;

    uint8_t *tmp = s->d_old;
    s->d_old = s->d_new;
    s->d_new = tmp;
    s->host_valid = 0;
    s->kernel_ready = 0;
}

extern "C" void sim_device_sync(const Sim *s)
{
    (void)s;
    cudaDeviceSynchronize();
}

extern "C" void sim_device_times(const Sim *s, double *t_kernel, double *t_with_copies)
{
    /* finish_kernel_timer writes through the pointer; the header takes const
       because the CPU-facing call only reads. The timer fields are a cache. */
    finish_kernel_timer((Sim *)s);
    *t_kernel = s->t_kernel;
    *t_with_copies = s->t_h2d + s->t_kernel + s->t_d2h;
}

extern "C" int sim_steps_done(const Sim *s)
{
    return s->step;
}

extern "C" void sim_reset_times(Sim *s)
{
    cudaDeviceSynchronize();
    free_step_events(s);
    s->kernel_ready = 0;
    s->t_kernel = 0.0;
    s->t_halo = 0.0;
    s->t_compute = 0.0;
}

extern "C" void sim_times(const Sim *s, double *t_halo, double *t_compute)
{
    finish_kernel_timer((Sim *)s);
    *t_halo = s->t_halo;
    *t_compute = s->t_compute;
}

extern "C" void sim_overlap_times(const Sim *s, double times[4])
{
    (void)s;
    times[0] = times[1] = times[2] = times[3] = 0.0;
}

extern "C" void sim_tile_counts(const Sim *s, long long *updated, long long *total)
{
    (void)s;
    *updated = 0;
    *total = 0;
}

extern "C" void sim_rank_grid(const Sim *s, int *px, int *py)
{
    (void)s;
    *px = 1;
    *py = 1;
}

extern "C" long long sim_count_burning(const Sim *s)
{
    return count_on_device((Sim *)s, 0);
}

extern "C" long long sim_count_burnt(const Sim *s)
{
    return count_on_device((Sim *)s, 1);
}

extern "C" uint64_t sim_checksum(const Sim *s)
{
    if (!pull_state((Sim *)s))
        return 0;
    return ff_checksum_grid(s->h_state, s->p.nx, s->p.ny, s->stride);
}

extern "C" uint8_t sim_state_at(const Sim *s, int x, int y)
{
    if (x < 0 || y < 0 || x >= s->p.nx || y >= s->p.ny)
        return STATE_UNBURNT;
    if (!pull_state((Sim *)s))
        return STATE_UNBURNT;
    return s->h_state[(size_t)(y + 1) * (size_t)s->stride + (size_t)(x + 1)];
}

extern "C" int sim_write_pgm(const Sim *s, const char *path)
{
    if (!pull_state((Sim *)s))
        return 1;
    size_t n = (size_t)s->p.nx * (size_t)s->p.ny;
    uint8_t *img = (uint8_t *)malloc(n);
    if (!img)
        return 1;
    for (int r = 1; r <= s->p.ny; r++)
        for (int c = 1; c <= s->p.nx; c++)
            img[(size_t)(r - 1) * (size_t)s->p.nx + (size_t)(c - 1)] =
                grey_of(s, r * s->stride + c);
    FILE *f = fopen(path, "wb");
    if (!f) {
        free(img);
        return 1;
    }
    fprintf(f, "P5\n%d %d\n255\n", s->p.nx, s->p.ny);
    int bad = fwrite(img, 1, n, f) != n;
    if (fclose(f) != 0)
        bad = 1;
    free(img);
    return bad;
}
