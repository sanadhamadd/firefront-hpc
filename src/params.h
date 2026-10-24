#ifndef FF_PARAMS_H
#define FF_PARAMS_H

#include <stdint.h>

typedef struct {
    int nx, ny;                 /* grid size in cells */
    int steps;                  /* number of time steps */
    int burn_steps;             /* how long a cell stays alight */
    int report_every;           /* progress line every this many steps, 0 = never */
    uint64_t seed;

    float cell_size;            /* metres */
    float wind_speed;           /* m/s */
    float wind_dir_deg;         /* direction the wind blows towards, 0 = east, 90 = north */
    float humidity;             /* 0..1, damps ignition */
    float p0;                   /* base ignition probability */
    float wind_coeff;           /* strength of the wind effect */
    float slope_coeff;          /* strength of the slope effect */

    int ignite_x, ignite_y;     /* first burning cell, -1 = default place */
    int river;                  /* 1 = put a firebreak column into the landscape */
    const char *snapshot;       /* write the final state as a PGM image, or NULL */
} Params;

void params_defaults(Params *p);

/* returns 0 on success, 1 if the program should stop (help or bad option) */
int params_parse(Params *p, int argc, char **argv);

#endif
