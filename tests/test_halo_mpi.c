/*
 * Halo exchange check with real MPI ranks, e.g.  mpirun -np 6 build/test_halo_mpi
 *
 * Every own cell gets a value made from its global position. After one exchange, every
 * border cell that lies inside the whole grid must hold the value of that global cell
 * (edges and corners included), and every border cell outside the grid must still be 0.
 * Done for strips and blocks on several grid sizes, twice in a row to catch stale borders.
 */
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>

#include "decomp.h"
#include "halo.h"
#include "rng.h"

/* never 0, so a border cell that was not filled shows up */
static uint8_t cell_value(int gx, int gy, int round)
{
    uint64_t h = mix64(((uint64_t)(uint32_t)gx << 32) | (uint32_t)gy) + (uint64_t)round;
    return (uint8_t)(1 + h % 255);
}

static int check(int gnx, int gny, int kind)
{
    Decomp d;
    if (decomp_init(&d, gnx, gny, kind) != 0)
        return -1;
    Halo h;
    halo_init(&h, &d);

    int stride = d.nx + 2;
    uint8_t *grid = calloc((size_t)stride * (d.ny + 2), 1);
    int errors = 0;

    for (int round = 0; round < 2; round++) {
        for (int r = 1; r <= d.ny; r++)
            for (int c = 1; c <= d.nx; c++)
                grid[r * stride + c] = cell_value(d.x0 + c - 1, d.y0 + r - 1, round);

        halo_exchange(&h, &d, grid);

        for (int r = 0; r < d.ny + 2; r++) {
            for (int c = 0; c < d.nx + 2; c++) {
                int border = (r == 0 || r == d.ny + 1 || c == 0 || c == d.nx + 1);
                if (!border) continue;
                int gx = d.x0 + c - 1, gy = d.y0 + r - 1;
                int inside = (gx >= 0 && gx < gnx && gy >= 0 && gy < gny);
                uint8_t want = inside ? cell_value(gx, gy, round) : 0;
                if (grid[r * stride + c] != want) errors++;
            }
        }
    }

    free(grid);
    halo_free(&h);
    decomp_free(&d);

    int total;
    MPI_Allreduce(&errors, &total, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
    return total;
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
            int errors = check(grids[g][0], grids[g][1], kind);
            if (rank == 0) {
                if (errors < 0)
                    printf("skip: %d x %d too small for %d ranks as %s\n", grids[g][0], grids[g][1], size, decomp_name(kind));
                else
                    printf("%s halo, %d ranks, %d x %d, %s%s\n", errors ? "FAIL:" : "ok:  ", size,
                           grids[g][0], grids[g][1], decomp_name(kind), errors ? " (wrong border cells)" : "");
            }
            if (errors > 0) failures++;
        }
    }

    MPI_Finalize();
    return failures ? 1 : 0;
}
