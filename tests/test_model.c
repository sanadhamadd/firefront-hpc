/* Checks for the model. Build and run with: make test */
#include <stdio.h>
#include <stdlib.h>

#include "landscape.h"
#include "params.h"
#include "rng.h"
#include "sim.h"

static int failures = 0;

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("  FAIL: %s (line %d)\n", msg, __LINE__); failures++; } \
} while (0)

static Params small_params(void)
{
    Params p;
    params_defaults(&p);
    p.nx = 160;
    p.ny = 120;
    p.steps = 80;
    return p;
}

static void run(Sim *s, int steps)
{
    for (int i = 0; i < steps; i++)
        sim_step(s);
}

static void test_rng(void)
{
    printf("rng\n");
    CHECK(cell_uniform(1, 10, 3) == cell_uniform(1, 10, 3), "same input gives same number");
    CHECK(cell_uniform(1, 10, 3) != cell_uniform(1, 10, 4), "different step gives different number");
    CHECK(cell_uniform(1, 10, 3) != cell_uniform(2, 10, 3), "different seed gives different number");

    double sum = 0.0;
    int n = 1000000;
    for (int i = 0; i < n; i++) {
        float u = cell_uniform(7, (uint64_t)i, 1);
        CHECK(u >= 0.0f && u < 1.0f, "number is in [0, 1)");
        sum += u;
    }
    double mean = sum / n;
    CHECK(mean > 0.498 && mean < 0.502, "mean is close to 0.5");
}

static void test_repeatable(void)
{
    printf("repeatable\n");
    Params p = small_params();
    Sim *a = sim_create(&p);
    Sim *b = sim_create(&p);
    run(a, p.steps);
    run(b, p.steps);
    CHECK(sim_checksum(a) == sim_checksum(b), "same seed gives the same checksum");
    CHECK(sim_count_burnt(a) > 100, "the fire actually spread");

    p.seed = 43;
    Sim *c = sim_create(&p);
    run(c, p.steps);
    CHECK(sim_checksum(a) != sim_checksum(c), "another seed gives another result");
    sim_free(a); sim_free(b); sim_free(c);
}

static void test_burnt_never_decreases(void)
{
    printf("burnt cells never decrease\n");
    Params p = small_params();
    Sim *s = sim_create(&p);
    long long last = 0;
    int ok = 1;
    for (int i = 0; i < p.steps; i++) {
        sim_step(s);
        long long now = sim_count_burnt(s);
        if (now < last) ok = 0;
        last = now;
    }
    CHECK(ok, "burnt count went down");
    sim_free(s);
}

static void test_fire_goes_out(void)
{
    printf("fire goes out\n");
    Params p = small_params();
    p.nx = 60; p.ny = 60; p.steps = 600; p.river = 0;
    p.ignite_x = 30; p.ignite_y = 30;
    p.humidity = 0.9f;          /* damp: the fire dies quickly */
    Sim *s = sim_create(&p);
    run(s, p.steps);
    CHECK(sim_count_burning(s) == 0, "nothing is burning at the end");
    sim_free(s);
}

static void test_wind(void)
{
    printf("wind pushes the fire downwind\n");
    Params p = small_params();
    p.nx = 161; p.ny = 161; p.river = 0;
    p.ignite_x = 80; p.ignite_y = 80;
    p.wind_speed = 8.0f;
    p.wind_dir_deg = 0.0f;      /* towards east */
    Sim *s = sim_create(&p);
    run(s, 50);

    int east = 0, west = 0;
    for (int y = 0; y < p.ny; y++) {
        for (int x = 0; x < p.nx; x++) {
            if (sim_state_at(s, x, y) == 0) continue;
            if (x - 81 > east) east = x - 81;
            if (79 - x > west) west = 79 - x;
        }
    }
    printf("  reach east %d cells, west %d cells\n", east, west);
    CHECK(east > west + 10, "the fire reaches further east than west");
    sim_free(s);
}

static void test_firebreak(void)
{
    printf("fire does not cross the firebreak\n");
    Params p = small_params();
    p.nx = 120; p.ny = 60; p.steps = 300; p.wind_speed = 0.0f;
    p.river = 1;
    p.ignite_x = 20; p.ignite_y = 30;
    Sim *s = sim_create(&p);
    run(s, p.steps);

    int river = landscape_river_column(p.nx);
    long long beyond = 0;
    for (int y = 0; y < p.ny; y++)
        for (int x = river + 3; x < p.nx; x++)
            if (sim_state_at(s, x, y) != 0) beyond++;
    printf("  burnt %lld cells, %lld of them beyond the river\n", sim_count_burnt(s), beyond);
    CHECK(sim_count_burnt(s) > 100, "the fire grew on its side of the river");
    CHECK(beyond == 0, "no cell beyond the river caught fire");
    sim_free(s);
}

static void test_ignitions(void)
{
    printf("several ignitions\n");
    Params p = small_params();
    p.nx = 256; p.ny = 256; p.steps = 200;
    Sim *one = sim_create(&p);
    run(one, p.steps);

    p.ignitions = 16;
    Sim *a = sim_create(&p);
    Sim *b = sim_create(&p);
    run(a, p.steps);
    run(b, p.steps);
    printf("  burnt with 1 ignition %lld, with 16 ignitions %lld\n",
           sim_count_burnt(one), sim_count_burnt(a));
    CHECK(sim_count_burnt(a) > sim_count_burnt(one), "16 ignitions burn more than 1");
    CHECK(sim_checksum(a) == sim_checksum(b), "same seed gives the same checksum with 16 ignitions");

    int river = landscape_river_column(p.nx);
    int on_river = 0, x, y;
    for (int k = 0; k < p.ignitions; k++) {
        sim_ignition_place(&p, k, &x, &y);
        if (x + 2 >= river && x < river + 3) on_river++;
    }
    CHECK(on_river == 0, "no ignition patch touches the river");
    sim_free(one); sim_free(a); sim_free(b);
}

/*
 * Every rank builds only its own block of the landscape, plus a border of one cell.
 * The values must be the same as in the whole grid at the same global position,
 * including border cells that belong to a neighbouring rank (their elevation is used
 * by the slope term). Border cells outside the whole grid must have no fuel and no height.
 */
static void test_landscape_blocks(void)
{
    printf("landscape blocks match the whole grid\n");
    Params p = small_params();
    p.nx = 97; p.ny = 61;                       /* the river is at column 61 */
    int gstride = p.nx + 2;
    size_t gcells = (size_t)gstride * (p.ny + 2);
    float *gfuel = malloc(gcells * sizeof(float));
    float *gelev = malloc(gcells * sizeof(float));
    landscape_fill(gfuel, gelev, p.nx, p.ny, 0, 0, &p);

    /* x0, y0, nx, ny: corners, edges, the middle, a block cutting the river, single rows */
    int blocks[][4] = { { 0, 0, 20, 15 }, { 77, 0, 20, 15 }, { 0, 46, 20, 15 }, { 77, 46, 20, 15 },
                        { 30, 20, 25, 10 }, { 58, 5, 8, 40 }, { 0, 30, 97, 1 }, { 40, 0, 1, 61 },
                        { 0, 0, 97, 61 } };
    int nblocks = (int)(sizeof blocks / sizeof blocks[0]);
    int wrong = 0;
    for (int b = 0; b < nblocks; b++) {
        int x0 = blocks[b][0], y0 = blocks[b][1], nx = blocks[b][2], ny = blocks[b][3];
        int stride = nx + 2;
        size_t cells = (size_t)stride * (ny + 2);
        float *fuel = malloc(cells * sizeof(float));
        float *elev = malloc(cells * sizeof(float));
        landscape_fill(fuel, elev, nx, ny, x0, y0, &p);
        for (int r = 0; r < ny + 2; r++) {
            for (int c = 0; c < nx + 2; c++) {
                int gx = x0 + c - 1, gy = y0 + r - 1;
                float want_fuel = 0.0f, want_elev = 0.0f;
                if (gx >= 0 && gx < p.nx && gy >= 0 && gy < p.ny) {
                    want_fuel = gfuel[(size_t)(gy + 1) * gstride + (gx + 1)];
                    want_elev = gelev[(size_t)(gy + 1) * gstride + (gx + 1)];
                }
                if (fuel[r * stride + c] != want_fuel || elev[r * stride + c] != want_elev)
                    wrong++;
            }
        }
        free(fuel);
        free(elev);
    }
    printf("  %d blocks, %d cells differ\n", nblocks, wrong);
    CHECK(wrong == 0, "a block and its border have the same fuel and elevation as the whole grid");
    free(gfuel);
    free(gelev);
}

int main(void)
{
    test_rng();
    test_repeatable();
    test_burnt_never_decreases();
    test_fire_goes_out();
    test_wind();
    test_firebreak();
    test_ignitions();
    test_landscape_blocks();

    if (failures) {
        printf("\n%d check(s) failed\n", failures);
        return 1;
    }
    printf("\nall checks passed\n");
    return 0;
}
