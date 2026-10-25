#include "sim.h"

#include <stdio.h>
#include <stdlib.h>

#include "landscape.h"
#include "rng.h"
#include "rules.h"

struct Sim {
    Params p;
    Rules rules;
    int stride;            /* nx + 2, the grids have a border of one cell */
    int step;              /* steps done so far */
    uint8_t *old_state;
    uint8_t *new_state;
    float *fuel;
    float *elev;
};

static size_t grid_cells(const Params *p)
{
    return (size_t)(p->nx + 2) * (size_t)(p->ny + 2);
}

/* set a 3 x 3 patch to burning; x, y is its top left cell (global, 0-based) */
static void ignite_patch(Sim *s, int ix, int iy)
{
    for (int dy = 0; dy < 3; dy++) {
        for (int dx = 0; dx < 3; dx++) {
            int x = ix + dx, y = iy + dy;
            if (x < s->p.nx && y < s->p.ny)
                s->old_state[(y + 1) * s->stride + (x + 1)] = 1;
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
    s->stride = p->nx + 2;
    s->step = 0;
    rules_init(&s->rules, p);

    size_t n = grid_cells(p);
    s->old_state = calloc(n, 1);
    s->new_state = calloc(n, 1);
    s->fuel = malloc(n * sizeof(float));
    s->elev = malloc(n * sizeof(float));
    if (!s->old_state || !s->new_state || !s->fuel || !s->elev) {
        sim_free(s);
        return NULL;
    }

    landscape_fill(s->fuel, s->elev, p->nx, p->ny, 0, 0, p);

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
    free(s);
}

void sim_step(Sim *s)
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

    s->step++;
    const uint64_t step = (uint64_t)s->step;

#ifdef _OPENMP
#pragma omp parallel for schedule(static)
#endif
    for (int r = 1; r <= p->ny; r++) {
        for (int c = 1; c <= p->nx; c++) {
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
                    uint64_t cell = (uint64_t)(r - 1) * (uint64_t)p->nx + (uint64_t)(c - 1);
                    if (cell_uniform(p->seed, cell, step) < 1.0f - keep)
                        new_[i] = 1;
                }
            }
        }
    }

    uint8_t *tmp = s->old_state;
    s->old_state = s->new_state;
    s->new_state = tmp;
}

int sim_steps_done(const Sim *s)
{
    return s->step;
}

long long sim_count_burning(const Sim *s)
{
    long long n = 0;
    for (int r = 1; r <= s->p.ny; r++)
        for (int c = 1; c <= s->p.nx; c++)
            if (is_burning(s->old_state[r * s->stride + c], s->rules.burn_steps))
                n++;
    return n;
}

long long sim_count_burnt(const Sim *s)
{
    long long n = 0;
    for (int r = 1; r <= s->p.ny; r++)
        for (int c = 1; c <= s->p.nx; c++)
            if (s->old_state[r * s->stride + c] == STATE_BURNT)
                n++;
    return n;
}

uint64_t sim_checksum(const Sim *s)
{
    uint64_t sum = 0;
    for (int r = 1; r <= s->p.ny; r++) {
        for (int c = 1; c <= s->p.nx; c++) {
            uint64_t cell = (uint64_t)(r - 1) * (uint64_t)s->p.nx + (uint64_t)(c - 1);
            sum += mix64((cell << 8) | s->old_state[r * s->stride + c]);
        }
    }
    return sum;
}

uint8_t sim_state_at(const Sim *s, int x, int y)
{
    return s->old_state[(y + 1) * s->stride + (x + 1)];
}

int sim_write_pgm(const Sim *s, const char *path)
{
    FILE *f = fopen(path, "wb");
    if (!f) return 1;
    fprintf(f, "P5\n%d %d\n255\n", s->p.nx, s->p.ny);
    for (int r = 1; r <= s->p.ny; r++) {
        for (int c = 1; c <= s->p.nx; c++) {
            int i = r * s->stride + c;
            uint8_t st = s->old_state[i];
            uint8_t grey;
            if (st == STATE_BURNT)       grey = 25;     /* dark: burnt */
            else if (st >= 1)            grey = 110;    /* medium: burning */
            else if (s->fuel[i] <= 0.0f) grey = 150;    /* firebreak */
            else                         grey = 215;    /* light: unburnt */
            fputc(grey, f);
        }
    }
    fclose(f);
    return 0;
}
