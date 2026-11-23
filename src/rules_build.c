#include "rules.h"

/* Out of line so every build (serial, CUDA, OpenACC) gets the tables from gcc,
   with the same -ffp-contract=off flags as the rest of the CPU code. */
void rules_build(Rules *r, const Params *p)
{
    rules_init(r, p);
}
