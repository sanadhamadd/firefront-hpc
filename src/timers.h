#ifndef FF_TIMERS_H
#define FF_TIMERS_H

#include <time.h>

/* seconds from a clock that does not jump */
static inline double wall_seconds(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + 1e-9 * (double)t.tv_nsec;
}

#endif
