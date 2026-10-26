#ifndef FF_SIM_H
#define FF_SIM_H

#include <stdint.h>

#include "params.h"

typedef struct Sim Sim;

Sim *sim_create(const Params *p);
void sim_free(Sim *s);

/* advance the fire by one time step */
void sim_step(Sim *s);

int sim_steps_done(const Sim *s);

/* this rank's time in the halo exchange and in the cell updates, summed over the steps
   since the last sim_reset_times (seconds) */
void sim_reset_times(Sim *s);
void sim_times(const Sim *s, double *t_halo, double *t_compute);

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
