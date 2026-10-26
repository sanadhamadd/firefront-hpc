#ifndef FF_HALO_H
#define FF_HALO_H

#include <stdint.h>

#include "decomp.h"

/*
 * Halo exchange for a grid of one byte per cell with a border of one cell
 * (d->nx + 2 columns, d->ny + 2 rows).
 *
 * Two phases, so that corner cells arrive without diagonal messages:
 *   1. rows: the first own row goes north, the last own row goes south;
 *   2. columns, including the border rows just received: the first own column
 *      goes west, the last own column goes east.
 * A corner cell of the north-west neighbour reaches us through the west neighbour,
 * which got it from its north neighbour in phase 1.
 *
 * Border cells at the edge of the whole grid are never written, so they keep whatever
 * the grid held before (zero for the state grids, which come from calloc).
 * Without MPI everything here does nothing.
 */
typedef struct {
#ifdef USE_MPI
    MPI_Datatype column;        /* d->ny + 2 bytes, one per row */
#endif
    int ready;
} Halo;

void halo_init(Halo *h, const Decomp *d);
void halo_free(Halo *h);
void halo_exchange(const Halo *h, const Decomp *d, uint8_t *grid);

#endif
