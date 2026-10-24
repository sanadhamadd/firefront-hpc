#ifndef FF_RNG_H
#define FF_RNG_H

#include <stdint.h>

/* 64-bit mixing function (the finalizer of SplitMix64). */
static inline uint64_t mix64(uint64_t x)
{
    x ^= x >> 30;
    x *= 0xBF58476D1CE4E5B9ULL;
    x ^= x >> 27;
    x *= 0x94D049BB133111EBULL;
    x ^= x >> 31;
    return x;
}

/*
 * Random number in [0, 1) for one cell at one time step.
 *
 * It only depends on the seed, the global cell index and the step number, so
 * the result does not change when the grid is split over ranks or threads.
 */
static inline float cell_uniform(uint64_t seed, uint64_t cell, uint64_t step)
{
    uint64_t x = seed ^ (cell * 0x9E3779B97F4A7C15ULL);
    x ^= step * 0xD1B54A32D192ED03ULL;
    x = mix64(x);
    return (float)(x >> 40) * (1.0f / 16777216.0f);   /* 24 random bits */
}

#endif
