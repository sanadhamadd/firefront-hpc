#include "sim.h"

#include "landscape.h"
#include "rng.h"

/*
 * Top left cell of ignition patch k (0-based) when --ignitions is above 1.
 * The place only depends on the seed, k and the global grid size, so every
 * MPI rank can compute all of them and keep the ones inside its own part.
 * A place whose patch would touch the river is skipped and the next draw is used.
 * Moved out of sim.c so the GPU builds call this same function.
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
