#ifndef FF_RULES_H
#define FF_RULES_H

#include <math.h>
#include <stdint.h>

#include "params.h"

/* cell states: 0 = unburnt, 1..burn_steps = burning (age), BURNT = burnt out */
#define STATE_UNBURNT 0
#define STATE_BURNT   255

/* slopes are looked up in a table indexed by the height difference in whole metres */
#define SLOPE_MAX     60
#define SLOPE_ENTRIES (2 * SLOPE_MAX + 1)

/*
 * Everything the cell rule needs besides the grids. It is built once, so the
 * loops contain no exp() calls (this also keeps CPU and GPU results identical later on).
 */
typedef struct {
    int   burn_steps;
    float base;                              /* p0 * (1 - humidity) */
    float dir[8];                            /* wind factor * geometry weight per neighbour */
    int   diagonal[8];                       /* 1 if the neighbour is diagonal */
    float slope[2][SLOPE_ENTRIES];           /* [edge or diagonal][height difference] */
} Rules;

/* the eight neighbours as (row offset, column offset) */
static const int NB_DR[8] = { -1, -1, -1,  0, 0,  1, 1, 1 };
static const int NB_DC[8] = { -1,  0,  1, -1, 1, -1, 0, 1 };

static inline void rules_init(Rules *r, const Params *p)
{
    const float pi = 3.14159265358979f;
    float wx = cosf(p->wind_dir_deg * pi / 180.0f);   /* wind blows towards (east, north) */
    float wy = sinf(p->wind_dir_deg * pi / 180.0f);

    r->burn_steps = p->burn_steps;
    r->base = p->p0 * (1.0f - p->humidity);

    for (int d = 0; d < 8; d++) {
        float dist = sqrtf((float)(NB_DR[d] * NB_DR[d] + NB_DC[d] * NB_DC[d]));
        /* the fire moves from the neighbour to this cell: west if the neighbour
           is to the east, north if the neighbour is to the south */
        float sx = -(float)NB_DC[d] / dist;
        float sy = (float)NB_DR[d] / dist;
        float cos_angle = sx * wx + sy * wy;
        float wind = expf(p->wind_coeff * p->wind_speed * (cos_angle - 1.0f));
        r->dir[d] = wind / dist;
        r->diagonal[d] = (NB_DR[d] != 0 && NB_DC[d] != 0);
    }

    for (int k = 0; k < 2; k++) {
        float dist = (k == 0) ? 1.0f : 1.41421356f;
        for (int q = -SLOPE_MAX; q <= SLOPE_MAX; q++) {
            float tan_slope = (float)q / (dist * p->cell_size);
            r->slope[k][q + SLOPE_MAX] = expf(p->slope_coeff * tan_slope);
        }
    }
}

/* index into the slope table for a height difference (target minus neighbour, metres) */
static inline int slope_index(float rise)
{
    int q = (int)(rise >= 0.0f ? rise + 0.5f : rise - 0.5f);
    if (q > SLOPE_MAX) q = SLOPE_MAX;
    if (q < -SLOPE_MAX) q = -SLOPE_MAX;
    return q + SLOPE_MAX;
}

static inline int is_burning(uint8_t s, int burn_steps)
{
    return s >= 1 && s <= burn_steps;
}

#endif
