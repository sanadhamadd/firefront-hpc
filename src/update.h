#ifndef FF_UPDATE_H
#define FF_UPDATE_H

#include "rng.h"
#include "rules.h"

/* The cell rule from sim.c, shared with the GPU builds so there is one copy of it.
   always_inline on the CPU: Apple clang was about 13 % slower when this was an
   ordinary call (2048^2, 200 steps). On the device it is force-inlined into the kernel. */
#if defined(__CUDACC__)
#define FF_INLINE static __host__ __device__ __forceinline__
#elif defined(_OPENACC)
#define FF_INLINE static inline
#else
#define FF_INLINE static inline __attribute__((always_inline))
#endif

#ifdef _OPENACC
#pragma acc routine seq
#endif
FF_INLINE void ff_cell_update(
    const Rules *rules,
    const float *fuel,
    const float *elev,
    const uint8_t *old,
    uint8_t *new_,
    const int *offset,
    int B,
    int i,
    uint64_t seed,
    uint64_t cell,
    uint64_t step)
{
    uint8_t st = old[i];

    if (st == STATE_BURNT) {
        new_[i] = STATE_BURNT;
    } else if (st >= 1) {                       /* burning */
        new_[i] = (st >= B) ? STATE_BURNT : (uint8_t)(st + 1);
    } else if (fuel[i] <= 0.0f) {
        new_[i] = STATE_UNBURNT;                /* nothing here can burn */
    } else {
        float keep = 1.0f;                      /* chance of not catching fire */
        int any = 0;
        for (int d = 0; d < 8; d++) {
            if (!is_burning(old[i + offset[d]], B))
                continue;
            any = 1;
            float rise = elev[i] - elev[i + offset[d]];
            float prob = rules->base * fuel[i] * rules->dir[d]
                       * rules->slope[rules->diagonal[d]][slope_index(rise)];
            if (prob > 1.0f) prob = 1.0f;
            keep *= 1.0f - prob;
        }
        new_[i] = STATE_UNBURNT;
        if (any) {
            if (cell_uniform(seed, cell, step) < 1.0f - keep)
                new_[i] = 1;
        }
    }
}

/* Checksum of one whole grid with no halo from other ranks (x0 = y0 = 0).
   The same sum as sim_checksum in the serial build. Host only. */
static inline uint64_t ff_checksum_grid(const uint8_t *state, int nx, int ny, int stride)
{
    uint64_t sum = 0;
    for (int r = 1; r <= ny; r++) {
        for (int c = 1; c <= nx; c++) {
            uint64_t cell = (uint64_t)(r - 1) * (uint64_t)nx + (uint64_t)(c - 1);
            sum += mix64((cell << 8) | state[r * stride + c]);
        }
    }
    return sum;
}

#endif
