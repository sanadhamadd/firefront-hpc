#include "decomp.h"

#include <stdio.h>

void decomp_split(int n, int parts, int index, int *start, int *len)
{
    int base = n / parts;
    int extra = n % parts;
    *len = base + (index < extra ? 1 : 0);
    *start = index * base + (index < extra ? index : extra);
}

const char *decomp_name(int kind)
{
    return kind == DECOMP_STRIPS ? "strips" : "blocks";
}

#ifdef USE_MPI

/* choose the process grid; blocks put the larger factor along the longer side of the grid */
static void choose_grid(int size, int gnx, int gny, int kind, int *px, int *py)
{
    if (kind == DECOMP_STRIPS) {
        *px = 1;
        *py = size;
        return;
    }
    int dims[2] = { 0, 0 };
    MPI_Dims_create(size, 2, dims);         /* dims[0] >= dims[1] */
    if (gny >= gnx) {
        *py = dims[0];
        *px = dims[1];
    } else {
        *px = dims[0];
        *py = dims[1];
    }
}

int decomp_init(Decomp *d, int gnx, int gny, int kind)
{
    int world_rank, world_size;
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    d->kind = kind;
    d->comm = MPI_COMM_NULL;
    choose_grid(world_size, gnx, gny, kind, &d->px, &d->py);

    if (d->px > gnx || d->py > gny) {
        if (world_rank == 0)
            fprintf(stderr, "a %d x %d grid cannot be split into %d x %d %s (each rank needs at least one cell in each direction)\n",
                    gnx, gny, d->py, d->px, decomp_name(kind));
        return 1;
    }

    /* dimension 0 = rows of ranks (y), dimension 1 = columns of ranks (x); no wrap-around.
       reorder = 0 keeps rank numbers equal to MPI_COMM_WORLD, which makes logs easier to read. */
    int dims[2] = { d->py, d->px };
    int periods[2] = { 0, 0 };
    MPI_Cart_create(MPI_COMM_WORLD, 2, dims, periods, 0, &d->comm);
    MPI_Comm_rank(d->comm, &d->rank);
    MPI_Comm_size(d->comm, &d->size);

    int coords[2];
    MPI_Cart_coords(d->comm, d->rank, 2, coords);
    d->cy = coords[0];
    d->cx = coords[1];

    MPI_Cart_shift(d->comm, 0, 1, &d->north, &d->south);
    MPI_Cart_shift(d->comm, 1, 1, &d->west, &d->east);

    decomp_split(gnx, d->px, d->cx, &d->x0, &d->nx);
    decomp_split(gny, d->py, d->cy, &d->y0, &d->ny);
    return 0;
}

void decomp_free(Decomp *d)
{
    if (d->comm != MPI_COMM_NULL)
        MPI_Comm_free(&d->comm);
}

#else

int decomp_init(Decomp *d, int gnx, int gny, int kind)
{
    d->kind = kind;
    d->rank = 0;
    d->size = 1;
    d->px = d->py = 1;
    d->cx = d->cy = 0;
    d->x0 = d->y0 = 0;
    d->nx = gnx;
    d->ny = gny;
    d->north = d->south = d->west = d->east = NO_NEIGHBOUR;
    return 0;
}

void decomp_free(Decomp *d)
{
    (void)d;
}

#endif
