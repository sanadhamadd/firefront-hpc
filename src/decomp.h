#ifndef FF_DECOMP_H
#define FF_DECOMP_H

#ifdef USE_MPI
#include <mpi.h>
#define NO_NEIGHBOUR MPI_PROC_NULL
#else
#define NO_NEIGHBOUR (-1)
#endif

enum { DECOMP_STRIPS = 0, DECOMP_BLOCKS = 1 };

/*
 * How the global nx x ny grid is split over the ranks, and which part this rank owns.
 *
 * The ranks form a py x px process grid (py rows, px columns). Strips use px = 1, so
 * every rank gets whole grid rows. Rank (cy, cx) owns the global cells
 * x0 .. x0 + nx - 1 and y0 .. y0 + ny - 1. Row 0 of the process grid is at the top
 * (smallest y), so "north" is the rank above. Without MPI there is one rank that owns
 * the whole grid and has no neighbours.
 */
typedef struct {
    int kind;                       /* DECOMP_STRIPS or DECOMP_BLOCKS */
    int rank, size;                 /* in the Cartesian communicator */
    int px, py;                     /* process grid: columns and rows of ranks */
    int cx, cy;                     /* this rank's column and row in the process grid */
    int x0, y0;                     /* global position of this rank's first cell */
    int nx, ny;                     /* this rank's number of cells */
    int north, south, west, east;   /* neighbour ranks, NO_NEIGHBOUR at the grid edge */
#ifdef USE_MPI
    MPI_Comm comm;                  /* Cartesian communicator, MPI_COMM_NULL until set up */
#endif
} Decomp;

/*
 * Split n cells into parts pieces as evenly as possible; the first n % parts pieces get
 * one cell more. Gives the start and length of piece index.
 */
void decomp_split(int n, int parts, int index, int *start, int *len);

/*
 * Set up the split of a global gnx x gny grid. With MPI this is collective over
 * MPI_COMM_WORLD. Returns 0 on success, 1 if the grid is too small for the number of ranks
 * (every rank needs at least one row and one column); then every rank gets 1.
 */
int decomp_init(Decomp *d, int gnx, int gny, int kind);

void decomp_free(Decomp *d);

/* "strips" or "blocks" */
const char *decomp_name(int kind);

#endif
