#include "sim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "decomp.h"
#include "halo.h"
#include "landscape.h"
#include "rng.h"
#include "rules.h"
#include "timers.h"

struct Sim {
    Params p;              /* p.nx, p.ny are the size of the whole (global) grid */
    Rules rules;
    Decomp d;              /* this rank's block: d.nx x d.ny cells starting at d.x0, d.y0 */
    Halo halo;             /* how the border is filled from the neighbouring ranks */
    int stride;            /* d.nx + 2, the grids have a border of one cell */
    int step;              /* steps done so far */
    double t_halo;         /* seconds in the halo exchange since the last sim_reset_times */
    double t_compute;      /* seconds updating cells since the last sim_reset_times */
    uint8_t *old_state;
    uint8_t *new_state;
    float *fuel;
    float *elev;
};

static size_t grid_cells(const Decomp *d)
{
    return (size_t)(d->nx + 2) * (size_t)(d->ny + 2);
}

/* global index of local cell (r, c), r and c counted from the border (1 = first own cell) */
static uint64_t global_cell(const Sim *s, int r, int c)
{
    return (uint64_t)(s->d.y0 + r - 1) * (uint64_t)s->p.nx + (uint64_t)(s->d.x0 + c - 1);
}

/* add a value over all ranks (nothing to do without MPI) */
static long long sum_ranks(const Sim *s, long long local)
{
#ifdef USE_MPI
    long long total;
    MPI_Allreduce(&local, &total, 1, MPI_LONG_LONG, MPI_SUM, s->d.comm);
    return total;
#else
    (void)s;
    return local;
#endif
}

/*
 * Set a 3 x 3 patch to burning; x, y is its top left cell (global, 0-based).
 * Only the cells inside this rank's block are set, so a patch on a rank border
 * ends up split over the ranks that own its cells.
 */
static void ignite_patch(Sim *s, int ix, int iy)
{
    for (int dy = 0; dy < 3; dy++) {
        for (int dx = 0; dx < 3; dx++) {
            int x = ix + dx, y = iy + dy;
            if (x >= s->p.nx || y >= s->p.ny)
                continue;
            int lx = x - s->d.x0, ly = y - s->d.y0;
            if (lx >= 0 && lx < s->d.nx && ly >= 0 && ly < s->d.ny)
                s->old_state[(ly + 1) * s->stride + (lx + 1)] = 1;
        }
    }
}

/*
 * Top left cell of ignition patch k (0-based) when --ignitions is above 1.
 * The place only depends on the seed, k and the global grid size, so every
 * MPI rank can compute all of them and keep the ones inside its own part.
 * A place whose patch would touch the river is skipped and the next draw is used.
 */
void sim_ignition_place(const Params *p, int k, int *x, int *y)
{
    int river = landscape_river_column(p->nx);
    int found = 0;
    for (uint64_t draw = 0; ; draw++) {
        uint64_t h = mix64(p->seed ^ 0xA5A5F00DCAFE1234ULL
                           ^ (draw * 0x9E3779B97F4A7C15ULL));
        int px = (int)((h >> 32) % (uint64_t)(p->nx - 2));
        int py = (int)((h & 0xFFFFFFFFULL) % (uint64_t)(p->ny - 2));
        int on_river = p->river && px + 2 >= river && px < river + 3;
        if (on_river)
            continue;
        if (found == k) {
            *x = px;
            *y = py;
            return;
        }
        found++;
    }
}

Sim *sim_create(const Params *p)
{
    Sim *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    s->p = *p;
    if (decomp_init(&s->d, p->nx, p->ny, p->decomp) != 0) {
        free(s);
        return NULL;
    }
    s->stride = s->d.nx + 2;
    s->step = 0;
    rules_init(&s->rules, p);
    halo_init(&s->halo, &s->d);

    size_t n = grid_cells(&s->d);
    s->old_state = calloc(n, 1);
    s->new_state = calloc(n, 1);
    s->fuel = malloc(n * sizeof(float));
    s->elev = malloc(n * sizeof(float));
    if (!s->old_state || !s->new_state || !s->fuel || !s->elev) {
        sim_free(s);
        return NULL;
    }

    landscape_fill(s->fuel, s->elev, s->d.nx, s->d.ny, s->d.x0, s->d.y0, p);

    if (p->ignitions == 1) {
        /* one fire start, at the default place or at --ignite */
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
    return s;
}

void sim_free(Sim *s)
{
    if (!s) return;
    free(s->old_state);
    free(s->new_state);
    free(s->fuel);
    free(s->elev);
    halo_free(&s->halo);
    decomp_free(&s->d);
    free(s);
}

/*
 * Update the own cells in rows r0..r1 and columns c0..c1 (local, 1 = first own cell)
 * from old_state into new_state. The rows are shared among the OpenMP threads.
 * sim_step calls it once for the whole block; an overlapped version can call it
 * first for the inner cells and, after the halo has arrived, for the boundary ring.
 */
static void update_block(Sim *s, int r0, int r1, int c0, int c1, uint64_t step)
{
    const Params *p = &s->p;
    const Rules *rules = &s->rules;
    const int stride = s->stride;
    const int B = rules->burn_steps;
    const uint8_t *old = s->old_state;
    uint8_t *new_ = s->new_state;

    int offset[8];
    for (int d = 0; d < 8; d++)
        offset[d] = NB_DR[d] * stride + NB_DC[d];

#ifdef _OPENMP
#pragma omp parallel for schedule(static)
#endif
    for (int r = r0; r <= r1; r++) {
        for (int c = c0; c <= c1; c++) {
            int i = r * stride + c;
            uint8_t st = old[i];

            if (st == STATE_BURNT) {
                new_[i] = STATE_BURNT;
            } else if (st >= 1) {                       /* burning */
                new_[i] = (st >= B) ? STATE_BURNT : (uint8_t)(st + 1);
            } else if (s->fuel[i] <= 0.0f) {
                new_[i] = STATE_UNBURNT;                /* nothing here can burn */
            } else {
                float keep = 1.0f;                      /* chance of not catching fire */
                int any = 0;
                for (int d = 0; d < 8; d++) {
                    if (!is_burning(old[i + offset[d]], B))
                        continue;
                    any = 1;
                    float rise = s->elev[i] - s->elev[i + offset[d]];
                    float prob = rules->base * s->fuel[i] * rules->dir[d]
                               * rules->slope[rules->diagonal[d]][slope_index(rise)];
                    if (prob > 1.0f) prob = 1.0f;
                    keep *= 1.0f - prob;
                }
                new_[i] = STATE_UNBURNT;
                if (any) {
                    uint64_t cell = global_cell(s, r, c);
                    if (cell_uniform(p->seed, cell, step) < 1.0f - keep)
                        new_[i] = 1;
                }
            }
        }
    }
}

void sim_step(Sim *s)
{
    /* the border of old_state must hold the neighbours' current cells */
    double t0 = wall_seconds();
    halo_exchange(&s->halo, &s->d, s->old_state);
    double t1 = wall_seconds();

    s->step++;
    update_block(s, 1, s->d.ny, 1, s->d.nx, (uint64_t)s->step);
    double t2 = wall_seconds();

    s->t_halo += t1 - t0;
    s->t_compute += t2 - t1;

    uint8_t *tmp = s->old_state;
    s->old_state = s->new_state;
    s->new_state = tmp;
}

int sim_steps_done(const Sim *s)
{
    return s->step;
}

void sim_reset_times(Sim *s)
{
    s->t_halo = 0.0;
    s->t_compute = 0.0;
}

void sim_times(const Sim *s, double *t_halo, double *t_compute)
{
    *t_halo = s->t_halo;
    *t_compute = s->t_compute;
}

void sim_rank_grid(const Sim *s, int *px, int *py)
{
    *px = s->d.px;
    *py = s->d.py;
}

long long sim_count_burning(const Sim *s)
{
    long long n = 0;
    for (int r = 1; r <= s->d.ny; r++)
        for (int c = 1; c <= s->d.nx; c++)
            if (is_burning(s->old_state[r * s->stride + c], s->rules.burn_steps))
                n++;
    return sum_ranks(s, n);
}

long long sim_count_burnt(const Sim *s)
{
    long long n = 0;
    for (int r = 1; r <= s->d.ny; r++)
        for (int c = 1; c <= s->d.nx; c++)
            if (s->old_state[r * s->stride + c] == STATE_BURNT)
                n++;
    return sum_ranks(s, n);
}

uint64_t sim_checksum(const Sim *s)
{
    uint64_t sum = 0;
    for (int r = 1; r <= s->d.ny; r++) {
        for (int c = 1; c <= s->d.nx; c++) {
            uint64_t cell = global_cell(s, r, c);
            sum += mix64((cell << 8) | s->old_state[r * s->stride + c]);
        }
    }
#ifdef USE_MPI
    /* unsigned addition wraps around, so the order of the ranks does not matter */
    uint64_t total;
    MPI_Allreduce(&sum, &total, 1, MPI_UINT64_T, MPI_SUM, s->d.comm);
    sum = total;
#endif
    return sum;
}

uint8_t sim_state_at(const Sim *s, int x, int y)
{
    int lx = x - s->d.x0, ly = y - s->d.y0;
    if (lx < 0 || lx >= s->d.nx || ly < 0 || ly >= s->d.ny)
        return STATE_UNBURNT;                   /* not on this rank */
    return s->old_state[(ly + 1) * s->stride + (lx + 1)];
}

/* grey level of local cell i in the snapshot */
static uint8_t grey_of(const Sim *s, int i)
{
    uint8_t st = s->old_state[i];
    if (st == STATE_BURNT)       return 25;     /* dark: burnt */
    if (st >= 1)                 return 110;    /* medium: burning */
    if (s->fuel[i] <= 0.0f)      return 150;    /* firebreak */
    return 215;                                 /* light: unburnt */
}

static int write_image(const char *path, const uint8_t *img, int nx, int ny)
{
    FILE *f = fopen(path, "wb");
    if (!f) return 1;
    fprintf(f, "P5\n%d %d\n255\n", nx, ny);
    size_t n = (size_t)nx * (size_t)ny;
    int bad = (fwrite(img, 1, n, f) != n);
    if (fclose(f) != 0) bad = 1;
    return bad;
}

int sim_write_pgm(const Sim *s, const char *path)
{
    const Decomp *d = &s->d;
    size_t mine_n = (size_t)d->nx * (size_t)d->ny;
    uint8_t *mine = malloc(mine_n);
    if (!mine) return 1;
    for (int r = 1; r <= d->ny; r++)
        for (int c = 1; c <= d->nx; c++)
            mine[(size_t)(r - 1) * d->nx + (c - 1)] = grey_of(s, r * s->stride + c);

    int bad = 0;
#ifdef USE_MPI
    if (d->size > 1) {
        /* rank 0 collects every block, then copies each one to its place in the picture.
           Meant for pictures of small and medium grids, not for timed runs. */
        int box[4] = { d->x0, d->y0, d->nx, d->ny };
        int *boxes = NULL, *counts = NULL, *displs = NULL;
        uint8_t *blocks = NULL, *img = NULL;
        if (d->rank == 0) {
            boxes = malloc(sizeof(int) * 4 * d->size);
            counts = malloc(sizeof(int) * d->size);
            displs = malloc(sizeof(int) * d->size);
            blocks = malloc((size_t)s->p.nx * (size_t)s->p.ny);
            img = malloc((size_t)s->p.nx * (size_t)s->p.ny);
        }
        MPI_Gather(box, 4, MPI_INT, boxes, 4, MPI_INT, 0, d->comm);
        if (d->rank == 0) {
            int offset = 0;
            for (int k = 0; k < d->size; k++) {
                counts[k] = boxes[4 * k + 2] * boxes[4 * k + 3];
                displs[k] = offset;
                offset += counts[k];
            }
        }
        MPI_Gatherv(mine, (int)mine_n, MPI_UNSIGNED_CHAR, blocks, counts, displs,
                    MPI_UNSIGNED_CHAR, 0, d->comm);
        if (d->rank == 0) {
            for (int k = 0; k < d->size; k++) {
                int x0 = boxes[4 * k], y0 = boxes[4 * k + 1], bnx = boxes[4 * k + 2], bny = boxes[4 * k + 3];
                const uint8_t *b = blocks + displs[k];
                for (int y = 0; y < bny; y++)
                    memcpy(img + (size_t)(y0 + y) * s->p.nx + x0, b + (size_t)y * bnx, (size_t)bnx);
            }
            bad = write_image(path, img, s->p.nx, s->p.ny);
            free(boxes); free(counts); free(displs); free(blocks); free(img);
        }
        MPI_Bcast(&bad, 1, MPI_INT, 0, d->comm);
        free(mine);
        return bad;
    }
#endif
    bad = write_image(path, mine, d->nx, d->ny);
    free(mine);
    return bad;
}
