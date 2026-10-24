#ifndef FF_LANDSCAPE_H
#define FF_LANDSCAPE_H

#include "params.h"

/* Column where the synthetic firebreak ("river") starts. It is 3 cells wide. */
int landscape_river_column(int nx);

/*
 * Fill fuel (0..1) and elevation (metres) for the nx x ny interior of arrays
 * that have a one cell border (row length nx + 2). The values depend only on
 * the global cell position and the seed, so any part of the grid can be
 * generated on its own. x0, y0 is the global position of the first interior cell.
 */
void landscape_fill(float *fuel, float *elev, int nx, int ny, int x0, int y0,
                    const Params *p);

#endif
