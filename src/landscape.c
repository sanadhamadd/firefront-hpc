#include "landscape.h"

#include <math.h>

#include "rng.h"

/* random value in [0, 1) attached to a lattice point */
static float lattice(uint64_t seed, uint64_t salt, int ix, int iy)
{
    uint64_t key = ((uint64_t)(uint32_t)ix << 32) | (uint32_t)iy;
    uint64_t h = mix64(seed ^ (salt * 0x9E3779B97F4A7C15ULL) ^ key);
    return (float)(h >> 40) * (1.0f / 16777216.0f);
}

/* smooth value noise: random lattice values blended with a smoothstep */
static float value_noise(uint64_t seed, uint64_t salt, int x, int y, float len)
{
    float fx = (float)x / len;
    float fy = (float)y / len;
    int ix = (int)floorf(fx);
    int iy = (int)floorf(fy);
    float tx = fx - (float)ix;
    float ty = fy - (float)iy;
    tx = tx * tx * (3.0f - 2.0f * tx);
    ty = ty * ty * (3.0f - 2.0f * ty);

    float a = lattice(seed, salt, ix,     iy);
    float b = lattice(seed, salt, ix + 1, iy);
    float c = lattice(seed, salt, ix,     iy + 1);
    float d = lattice(seed, salt, ix + 1, iy + 1);
    float top = a + (b - a) * tx;
    float bottom = c + (d - c) * tx;
    return top + (bottom - top) * ty;
}

int landscape_river_column(int nx)
{
    return (int)((long long)nx * 63 / 100);
}

void landscape_fill(float *fuel, float *elev, int nx, int ny, int x0, int y0,
                    const Params *p)
{
    int stride = nx + 2;
    int river = landscape_river_column(p->nx);

#ifdef _OPENMP
#pragma omp parallel for schedule(static)
#endif
    for (int r = 0; r < ny + 2; r++) {
        for (int c = 0; c < nx + 2; c++) {
            int i = r * stride + c;
            int on_border = (r == 0 || r == ny + 1 || c == 0 || c == nx + 1);
            if (on_border) {
                fuel[i] = 0.0f;
                elev[i] = 0.0f;
                continue;
            }
            int gx = x0 + c - 1;
            int gy = y0 + r - 1;
            fuel[i] = 0.35f + 0.65f * value_noise(p->seed, 1, gx, gy, 48.0f);
            elev[i] = 120.0f * value_noise(p->seed, 2, gx, gy, 96.0f);
            if (p->river && gx >= river && gx < river + 3)
                fuel[i] = 0.0f;
        }
    }
}
