#include "params.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void params_defaults(Params *p)
{
    p->nx = 1024;
    p->ny = 1024;
    p->steps = 200;
    p->burn_steps = 3;
    p->report_every = 0;
    p->seed = 42;

    p->cell_size = 25.0f;
    p->wind_speed = 6.0f;
    p->wind_dir_deg = 0.0f;
    p->humidity = 0.2f;
    p->p0 = 0.8f;
    p->wind_coeff = 0.25f;
    p->slope_coeff = 1.5f;

    p->ignite_x = -1;
    p->ignite_y = -1;
    p->river = 1;
    p->snapshot = NULL;
    p->ignitions = 1;
}

static void usage(const char *prog)
{
    printf("usage: %s [options]\n\n", prog);
    printf("  --nx N --ny N         grid size in cells (default 1024 x 1024)\n");
    printf("  --steps N             number of time steps (default 200)\n");
    printf("  --seed N              random seed (default 42)\n");
    printf("  --burn-steps N        steps a cell stays alight, 1..250 (default 3)\n");
    printf("  --wind-speed V        wind speed in m/s (default 6)\n");
    printf("  --wind-dir DEG        direction the wind blows towards, 0 = east, 90 = north (default 0)\n");
    printf("  --humidity H          0..1 (default 0.2)\n");
    printf("  --p0 P                base ignition probability (default 0.8)\n");
    printf("  --cell-size M         cell size in metres (default 25)\n");
    printf("  --ignite X,Y          cell where the fire starts (default: left part, middle row)\n");
    printf("  --ignitions N         number of fire starts; N > 1 places them from the seed, off the river (default 1)\n");
    printf("  --river 0|1           firebreak column in the landscape (default 1)\n");
    printf("  --report-every N      print a progress line every N steps\n");
    printf("  --snapshot FILE       write the final state as a PGM image\n");
    printf("  --help\n");
}

static int is_option(const char *arg, const char *name)
{
    return strcmp(arg, name) == 0;
}

int params_parse(Params *p, int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (is_option(a, "--help") || is_option(a, "-h")) {
            usage(argv[0]);
            return 1;
        }
        if (i + 1 >= argc) {
            fprintf(stderr, "missing value for %s\n", a);
            return 1;
        }
        const char *v = argv[++i];

        if      (is_option(a, "--nx"))           p->nx = atoi(v);
        else if (is_option(a, "--ny"))           p->ny = atoi(v);
        else if (is_option(a, "--steps"))        p->steps = atoi(v);
        else if (is_option(a, "--seed"))         p->seed = strtoull(v, NULL, 10);
        else if (is_option(a, "--burn-steps"))   p->burn_steps = atoi(v);
        else if (is_option(a, "--wind-speed"))   p->wind_speed = (float)atof(v);
        else if (is_option(a, "--wind-dir"))     p->wind_dir_deg = (float)atof(v);
        else if (is_option(a, "--humidity"))     p->humidity = (float)atof(v);
        else if (is_option(a, "--p0"))           p->p0 = (float)atof(v);
        else if (is_option(a, "--cell-size"))    p->cell_size = (float)atof(v);
        else if (is_option(a, "--river"))        p->river = atoi(v);
        else if (is_option(a, "--report-every")) p->report_every = atoi(v);
        else if (is_option(a, "--snapshot"))     p->snapshot = v;
        else if (is_option(a, "--ignitions"))    p->ignitions = atoi(v);
        else if (is_option(a, "--ignite")) {
            if (sscanf(v, "%d,%d", &p->ignite_x, &p->ignite_y) != 2) {
                fprintf(stderr, "--ignite needs X,Y\n");
                return 1;
            }
        } else {
            fprintf(stderr, "unknown option %s\n", a);
            usage(argv[0]);
            return 1;
        }
    }

    if (p->nx < 4 || p->ny < 4 || p->steps < 0) {
        fprintf(stderr, "grid must be at least 4 x 4 and steps must not be negative\n");
        return 1;
    }
    if (p->burn_steps < 1 || p->burn_steps > 250) {
        fprintf(stderr, "--burn-steps must be between 1 and 250\n");
        return 1;
    }
    if (p->humidity < 0.0f || p->humidity > 1.0f) {
        fprintf(stderr, "--humidity must be between 0 and 1\n");
        return 1;
    }
    if (p->ignitions < 1) {
        fprintf(stderr, "--ignitions must be at least 1\n");
        return 1;
    }
    if (p->ignitions > 1 && p->ignite_x >= 0) {
        fprintf(stderr, "--ignite only works with one ignition; with --ignitions N > 1 the places come from the seed\n");
        return 1;
    }
    if (p->ignitions > 1 && p->river && p->nx < 8) {
        fprintf(stderr, "--ignitions N > 1 with a river needs --nx of at least 8\n");
        return 1;
    }
    return 0;
}
