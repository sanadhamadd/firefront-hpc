/* OpenACC port. Same step as the CUDA build: one parallel loop, two state buffers,
   fuel and elevation stay on the device. nvc -Mnofma is the stand-in for
   -ffp-contract=off. Not compiled on a machine without the NVIDIA HPC SDK. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <openacc.h>

#include "landscape.h"
#include "sim.h"
#include "timers.h"
#include "update.h"

struct Sim {
    Params p;
    Rules rules;
    int offset[8];
    int stride;
    int step;
    int n;
    int on_device;
    int src_is_0;     /* 1 = the latest state is h_state0 */
    int host_valid;
    double t_halo, t_compute;
    double t_h2d, t_d2h, t_kernel;
    float *h_fuel, *h_elev;
    uint8_t *h_state0, *h_state1;
};

static uint8_t *current_state(const Sim *s)
{
    return s->src_is_0 ? s->h_state0 : s->h_state1;
}

static void ignite_patch(Sim *s, int ix, int iy)
{
    for (int dy = 0; dy < 3; dy++) {
        for (int dx = 0; dx < 3; dx++) {
            int x = ix + dx, y = iy + dy;
            if (x >= s->p.nx || y >= s->p.ny)
                continue;
            s->h_state0[(y + 1) * s->stride + (x + 1)] = 1;
        }
    }
}

static uint8_t grey_of(const Sim *s, int i)
{
    uint8_t st = current_state(s)[i];
    if (st == STATE_BURNT)    return 25;
    if (st >= 1)              return 110;
    if (s->h_fuel[i] <= 0.0f) return 150;
    return 215;
}

static int pull_state(Sim *s)
{
    if (s->host_valid || !s->on_device)
        return 1;
    uint8_t *cur = current_state(s);
    int n = s->n;
    double t0 = wall_seconds();
#pragma acc update self(cur[0:n])
    s->t_d2h = wall_seconds() - t0;
    s->host_valid = 1;
    return 1;
}

Sim *sim_create(const Params *p)
{
    if (p->skip_tiles > 0) {
        fprintf(stderr, "--skip-tiles is a CPU-only optimisation (E8); the GPU build does not implement it\n");
        return NULL;
    }
    if ((size_t)(p->nx + 2) * (size_t)(p->ny + 2) > (size_t)2147483647) {
        fprintf(stderr, "grid is too large for the OpenACC kernel's 32-bit cell index\n");
        return NULL;
    }

    Sim *s = calloc(1, sizeof *s);
    if (!s)
        return NULL;
    s->p = *p;
    s->stride = p->nx + 2;
    s->n = s->stride * (p->ny + 2);
    s->src_is_0 = 1;
    rules_build(&s->rules, p);
    for (int d = 0; d < 8; d++)
        s->offset[d] = NB_DR[d] * s->stride + NB_DC[d];

    s->h_fuel = malloc((size_t)s->n * sizeof(float));
    s->h_elev = malloc((size_t)s->n * sizeof(float));
    s->h_state0 = calloc((size_t)s->n, 1);
    s->h_state1 = calloc((size_t)s->n, 1);
    if (!s->h_fuel || !s->h_elev || !s->h_state0 || !s->h_state1) {
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

    {
        float *fuel = s->h_fuel, *elev = s->h_elev;
        uint8_t *state0 = s->h_state0, *state1 = s->h_state1;
        int *offset = s->offset;
        Rules *rules = &s->rules;
        int n = s->n;
        double t0 = wall_seconds();
#pragma acc enter data copyin(fuel[0:n], elev[0:n], state0[0:n], offset[0:8], rules[0:1]) create(state1[0:n])
        s->t_h2d = wall_seconds() - t0;
        s->on_device = 1;
    }
    s->host_valid = 1;
    return s;
}

void sim_free(Sim *s)
{
    if (!s)
        return;
    if (s->on_device) {
        float *fuel = s->h_fuel, *elev = s->h_elev;
        uint8_t *state0 = s->h_state0, *state1 = s->h_state1;
        int *offset = s->offset;
        Rules *rules = &s->rules;
        int n = s->n;
#pragma acc exit data delete(fuel[0:n], elev[0:n], state0[0:n], state1[0:n], offset[0:8], rules[0:1])
    }
    free(s->h_fuel);
    free(s->h_elev);
    free(s->h_state0);
    free(s->h_state1);
    free(s);
}

void sim_step(Sim *s)
{
    s->step++;
    uint8_t *src = s->src_is_0 ? s->h_state0 : s->h_state1;
    uint8_t *dst = s->src_is_0 ? s->h_state1 : s->h_state0;
    float *fuel = s->h_fuel, *elev = s->h_elev;
    int *offset = s->offset;
    Rules *rules = &s->rules;
    int nx = s->p.nx, ny = s->p.ny, stride = s->stride, n = s->n;
    int B = s->rules.burn_steps;
    uint64_t seed = s->p.seed, step = (uint64_t)s->step;

    double t0 = wall_seconds();
#pragma acc parallel loop collapse(2) present(src[0:n], dst[0:n], fuel[0:n], elev[0:n], offset[0:8], rules[0:1])
    for (int r = 1; r <= ny; r++) {
        for (int c = 1; c <= nx; c++) {
            int i = r * stride + c;
            uint64_t cell = (uint64_t)(r - 1) * (uint64_t)nx + (uint64_t)(c - 1);
            ff_cell_update(rules, fuel, elev, src, dst, offset, B, i, seed, cell, step);
        }
    }
    s->t_kernel += wall_seconds() - t0;
    s->t_compute = s->t_kernel;
    s->src_is_0 = !s->src_is_0;
    s->host_valid = 0;
}

void sim_device_sync(const Sim *s)
{
    (void)s;
    acc_wait_all();
}

void sim_device_times(const Sim *s, double *t_kernel, double *t_with_copies)
{
    *t_kernel = s->t_kernel;
    *t_with_copies = s->t_h2d + s->t_kernel + s->t_d2h;
}

int sim_steps_done(const Sim *s)
{
    return s->step;
}

void sim_reset_times(Sim *s)
{
    acc_wait_all();
    /* Drop the warm-up loops. Later steps add to t_kernel again. */
    s->t_kernel = 0.0;
    s->t_compute = 0.0;
    s->t_halo = 0.0;
}

void sim_times(const Sim *s, double *t_halo, double *t_compute)
{
    *t_halo = s->t_halo;
    *t_compute = s->t_kernel;
}

void sim_overlap_times(const Sim *s, double times[4])
{
    (void)s;
    times[0] = times[1] = times[2] = times[3] = 0.0;
}

void sim_tile_counts(const Sim *s, long long *updated, long long *total)
{
    (void)s;
    *updated = 0;
    *total = 0;
}

void sim_rank_grid(const Sim *s, int *px, int *py)
{
    (void)s;
    *px = 1;
    *py = 1;
}

static long long count_where(Sim *s, int burnt)
{
    uint8_t *st = current_state(s);
    int nx = s->p.nx, ny = s->p.ny, stride = s->stride, n = s->n;
    int B = s->rules.burn_steps;
    long long total = 0;
#pragma acc parallel loop collapse(2) present(st[0:n]) reduction(+:total)
    for (int r = 1; r <= ny; r++) {
        for (int c = 1; c <= nx; c++) {
            uint8_t v = st[r * stride + c];
            if (burnt)
                total += (v == STATE_BURNT);
            else
                total += is_burning(v, B);
        }
    }
    return total;
}

long long sim_count_burning(const Sim *s)
{
    return count_where((Sim *)s, 0);
}

long long sim_count_burnt(const Sim *s)
{
    return count_where((Sim *)s, 1);
}

uint64_t sim_checksum(const Sim *s)
{
    if (!pull_state((Sim *)s))
        return 0;
    return ff_checksum_grid(current_state(s), s->p.nx, s->p.ny, s->stride);
}

uint8_t sim_state_at(const Sim *s, int x, int y)
{
    if (x < 0 || y < 0 || x >= s->p.nx || y >= s->p.ny)
        return STATE_UNBURNT;
    if (!pull_state((Sim *)s))
        return STATE_UNBURNT;
    return current_state(s)[(y + 1) * s->stride + (x + 1)];
}

int sim_write_pgm(const Sim *s, const char *path)
{
    if (!pull_state((Sim *)s))
        return 1;
    size_t n = (size_t)s->p.nx * (size_t)s->p.ny;
    uint8_t *img = malloc(n);
    if (!img)
        return 1;
    for (int r = 1; r <= s->p.ny; r++)
        for (int c = 1; c <= s->p.nx; c++)
            img[(size_t)(r - 1) * s->p.nx + (c - 1)] = grey_of(s, r * s->stride + c);
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
