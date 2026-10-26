/* Checks for the grid split that do not need MPI. Run with: make test */
#include <stdio.h>

#include "decomp.h"

static int failures = 0;

#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("  FAIL: %s (line %d)\n", msg, __LINE__); failures++; } \
} while (0)

/* every split of n cells into parts pieces covers 0..n-1 once, and piece sizes differ by at most 1 */
static void test_split(void)
{
    printf("split of a length into pieces\n");
    int bad = 0;
    for (int n = 1; n <= 300; n++) {
        for (int parts = 1; parts <= n && parts <= 40; parts++) {
            int next = 0, smallest = n, largest = 0;
            for (int i = 0; i < parts; i++) {
                int start, len;
                decomp_split(n, parts, i, &start, &len);
                if (start != next || len < 1) bad++;
                next = start + len;
                if (len < smallest) smallest = len;
                if (len > largest) largest = len;
            }
            if (next != n || largest - smallest > 1) bad++;
        }
    }
    CHECK(bad == 0, "pieces are contiguous, non-empty, cover the length and differ by at most one");

    int start, len;
    decomp_split(10, 3, 0, &start, &len);
    CHECK(start == 0 && len == 4, "10 cells in 3 pieces: first piece is 0..3");
    decomp_split(10, 3, 2, &start, &len);
    CHECK(start == 7 && len == 3, "10 cells in 3 pieces: last piece is 7..9");
}

static void test_single_rank(void)
{
    printf("one rank owns the whole grid\n");
    Decomp d;
    CHECK(decomp_init(&d, 203, 157, DECOMP_BLOCKS) == 0, "init works");
    CHECK(d.size == 1 && d.px == 1 && d.py == 1, "one rank in a 1 x 1 process grid");
    CHECK(d.x0 == 0 && d.y0 == 0 && d.nx == 203 && d.ny == 157, "the block is the whole grid");
    CHECK(d.north == NO_NEIGHBOUR && d.south == NO_NEIGHBOUR &&
          d.west == NO_NEIGHBOUR && d.east == NO_NEIGHBOUR, "no neighbours");
    decomp_free(&d);
}

int main(void)
{
    test_split();
    test_single_rank();
    if (failures) {
        printf("\n%d check(s) failed\n", failures);
        return 1;
    }
    printf("\nall decomposition checks passed\n");
    return 0;
}
