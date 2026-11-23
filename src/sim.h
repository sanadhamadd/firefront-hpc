#ifndef FF_SIM_H
#define FF_SIM_H

#include <stdint.h>

#include "params.h"

typedef struct Sim Sim;

Sim *sim_create(const Params *p);
void sim_free(Sim *s);

/* advance the fire by one time step */
void sim_step(Sim *s);

#if defined(USE_CUDA) || defined(USE_ACC)
/* Wait until the device has finished the steps already launched.
   The CPU builds do not have this: their sim_step returns only when the step is done. */
void sim_device_sync(const Sim *s);
/* Timed steps only, from device events (CUDA) or from the loop itself (OpenACC),
   and that time plus the one upload of the grids and the one download of the state. */
void sim_device_times(const Sim *s, double *t_kernel, double *t_with_copies);
#endif

int sim_steps_done(const Sim *s);

/* this rank's time in the halo exchange and in the cell updates, summed over the steps
   since the last sim_reset_times (seconds) */
void sim_reset_times(Sim *s);
void sim_times(const Sim *s, double *t_halo, double *t_compute);
/* Local overlap phase totals in order: posting, waiting, interior, boundary. */
void sim_overlap_times(const Sim *s, double times[4]);
/* with --skip-tiles: tiles computed and tiles looked at since the last sim_reset_times */
void sim_tile_counts(const Sim *s, long long *updated, long long *total);

/* process grid: px columns x py rows of ranks (1 x 1 without MPI) */
void sim_rank_grid(const Sim *s, int *px, int *py);
long long sim_count_burning(const Sim *s);
long long sim_count_burnt(const Sim *s);

/* sum of a hash over all cells; does not depend on how the grid is stored or split */
uint64_t sim_checksum(const Sim *s);

/* state of one cell, x = column, y = row, both 0-based */
uint8_t sim_state_at(const Sim *s, int x, int y);

/* top left cell (global, 0-based) of ignition patch k when p->ignitions > 1 */
void sim_ignition_place(const Params *p, int k, int *x, int *y);

/* write the current state as a grey scale PGM image; returns 0 on success.
   With MPI every rank must call it: rank 0 collects the grid and writes the file. */
int sim_write_pgm(const Sim *s, const char *path);

#endif
