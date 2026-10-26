/*
 * Checks the grid split with real MPI ranks. Run with any number of ranks, e.g.
 *   mpirun -np 6 build/test_decomp_mpi
 * For several grid sizes (some that do not divide evenly) and both strips and blocks,
 * rank 0 collects every rank's block and neighbours and checks that the blocks tile the
 * grid exactly once and that the neighbours really touch.
 */
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>

#include "decomp.h"

enum { X0, Y0, NX, NY, NORTH, SOUTH, WEST, EAST, CX, CY, NFIELDS };

static int check_split(int gnx, int gny, int kind, int rank, int size)
{
    Decomp d;
    int status = decomp_init(&d, gnx, gny, kind);
    if (status != 0)
        return -1;                          /* grid too small for this many ranks */

    int mine[NFIELDS] = { d.x0, d.y0, d.nx, d.ny, d.north, d.south, d.west, d.east, d.cx, d.cy };
    int *all = (rank == 0) ? malloc(sizeof(int) * NFIELDS * size) : NULL;
    MPI_Gather(mine, NFIELDS, MPI_INT, all, NFIELDS, MPI_INT, 0, d.comm);

    int errors = 0;
    if (rank == 0) {
        /* every cell owned by exactly one rank */
        unsigned char *owned = calloc((size_t)gnx * gny, 1);
        for (int r = 0; r < size; r++) {
            int *b = all + r * NFIELDS;
            if (b[NX] < 1 || b[NY] < 1) errors++;
            for (int y = b[Y0]; y < b[Y0] + b[NY]; y++)
                for (int x = b[X0]; x < b[X0] + b[NX]; x++)
                    owned[(size_t)y * gnx + x]++;
        }
        for (size_t i = 0; i < (size_t)gnx * gny; i++)
            if (owned[i] != 1) { errors++; break; }
        free(owned);

        /* neighbours touch along a whole edge, and the grid edge has no neighbour */
        for (int r = 0; r < size; r++) {
            int *b = all + r * NFIELDS;
            if (b[EAST] == MPI_PROC_NULL) {
                if (b[X0] + b[NX] != gnx) errors++;
            } else {
                int *e = all + b[EAST] * NFIELDS;
                if (e[X0] != b[X0] + b[NX] || e[Y0] != b[Y0] || e[NY] != b[NY] || e[WEST] != r) errors++;
            }
            if (b[SOUTH] == MPI_PROC_NULL) {
                if (b[Y0] + b[NY] != gny) errors++;
            } else {
                int *s = all + b[SOUTH] * NFIELDS;
                if (s[Y0] != b[Y0] + b[NY] || s[X0] != b[X0] || s[NX] != b[NX] || s[NORTH] != r) errors++;
            }
            if (b[WEST] == MPI_PROC_NULL && b[X0] != 0) errors++;
            if (b[NORTH] == MPI_PROC_NULL && b[Y0] != 0) errors++;
            if (kind == DECOMP_STRIPS && (b[NX] != gnx || b[WEST] != MPI_PROC_NULL || b[EAST] != MPI_PROC_NULL))
                errors++;
        }
        free(all);
    }
    decomp_free(&d);
    MPI_Bcast(&errors, 1, MPI_INT, 0, MPI_COMM_WORLD);
    return errors;
}

int main(int argc, char **argv)
{
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    int grids[][2] = { { 64, 64 }, { 203, 157 }, { 157, 203 }, { 1000, 9 }, { 17, 500 } };
    int ngrids = (int)(sizeof grids / sizeof grids[0]);
    int failures = 0;

    for (int g = 0; g < ngrids; g++) {
        for (int kind = DECOMP_STRIPS; kind <= DECOMP_BLOCKS; kind++) {
            int gnx = grids[g][0], gny = grids[g][1];
            int errors = check_split(gnx, gny, kind, rank, size);
            if (rank == 0) {
                if (errors < 0)
                    printf("skip: %d x %d is too small for %d ranks as %s\n", gnx, gny, size, decomp_name(kind));
                else if (errors == 0)
                    printf("ok:   %d ranks, %d x %d, %s\n", size, gnx, gny, decomp_name(kind));
                else
                    printf("FAIL: %d ranks, %d x %d, %s (%d problems)\n", size, gnx, gny, decomp_name(kind), errors);
            }
            if (errors > 0) failures++;
        }
    }

    /* a grid with fewer rows than ranks must be refused by every rank, not crash */
    if (size > 1) {
        Decomp d;
        int refused = decomp_init(&d, 50, size - 1, DECOMP_STRIPS);
        int all_refused;
        MPI_Allreduce(&refused, &all_refused, 1, MPI_INT, MPI_MIN, MPI_COMM_WORLD);
        if (rank == 0)
            printf("%s %d rows for %d ranks as strips is refused\n", all_refused ? "ok:  " : "FAIL:", size - 1, size);
        if (!all_refused) failures++;
        else if (!refused) decomp_free(&d);
    }

    MPI_Finalize();
    return failures ? 1 : 0;
}
