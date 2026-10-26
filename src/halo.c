#include "halo.h"

#ifdef USE_MPI

enum { TAG_TO_NORTH = 1, TAG_TO_SOUTH, TAG_TO_WEST, TAG_TO_EAST };

void halo_init(Halo *h, const Decomp *d)
{
    MPI_Type_vector(d->ny + 2, 1, d->nx + 2, MPI_UNSIGNED_CHAR, &h->column);
    MPI_Type_commit(&h->column);
    h->ready = 1;
}

void halo_free(Halo *h)
{
    if (h->ready)
        MPI_Type_free(&h->column);
    h->ready = 0;
}

void halo_exchange(const Halo *h, const Decomp *d, uint8_t *grid)
{
    const int stride = d->nx + 2;
    const int nx = d->nx, ny = d->ny;

    /* phase 1: rows (own columns only), MPI_PROC_NULL makes the grid edge a no-op */
    if (d->py > 1) {
        MPI_Sendrecv(&grid[1 * stride + 1], nx, MPI_UNSIGNED_CHAR, d->north, TAG_TO_NORTH,
                     &grid[(ny + 1) * stride + 1], nx, MPI_UNSIGNED_CHAR, d->south, TAG_TO_NORTH,
                     d->comm, MPI_STATUS_IGNORE);
        MPI_Sendrecv(&grid[ny * stride + 1], nx, MPI_UNSIGNED_CHAR, d->south, TAG_TO_SOUTH,
                     &grid[0 * stride + 1], nx, MPI_UNSIGNED_CHAR, d->north, TAG_TO_SOUTH,
                     d->comm, MPI_STATUS_IGNORE);
    }

    /* phase 2: whole columns, border rows included, so the corners travel on */
    if (d->px > 1) {
        MPI_Sendrecv(&grid[1], 1, h->column, d->west, TAG_TO_WEST,
                     &grid[nx + 1], 1, h->column, d->east, TAG_TO_WEST,
                     d->comm, MPI_STATUS_IGNORE);
        MPI_Sendrecv(&grid[nx], 1, h->column, d->east, TAG_TO_EAST,
                     &grid[0], 1, h->column, d->west, TAG_TO_EAST,
                     d->comm, MPI_STATUS_IGNORE);
    }
}

#else

void halo_init(Halo *h, const Decomp *d)
{
    (void)d;
    h->ready = 1;
}

void halo_free(Halo *h)
{
    h->ready = 0;
}

void halo_exchange(const Halo *h, const Decomp *d, uint8_t *grid)
{
    (void)h;
    (void)d;
    (void)grid;
}

#endif
