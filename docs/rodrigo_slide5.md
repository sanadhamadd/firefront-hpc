# Slide 5 — GPU, lessons, EuroHPC

Speaker notes for Rodrigo. One slide. The GPU numbers go on the slide only after `python tools/plot_e10.py` has written `results/tables/e10_summary.csv`. Until then, say the jobs are submitted and show the CPU column of the matrix, which is already measured.

## What to put on the slide

- Title: one more technology, and what we would take to a larger machine.
- The E1 picture, once the logs exist: median of 3 on one RTX 6000 Ada, kernel time and time with the two copies, next to the best one-node CPU time (MPI, 32 ranks, blocks, 2.62 s). Error bars are min–max. Figure: `results/figures/e10_time.png`.
- The matrix from §8, cut to one line per technology: speed-up, effort, what stops it. CPU rows are filled. GPU rows wait for `e10_summary.csv`.
- Three lessons, below.
- Sanad's line, still a placeholder: **EuroHPC node-hours: [Sanad fills this].**

## What to say

The extra technology is a GPU port of the same cell update, not a new fire model. The grid stays on the device for every step. The checksum is the serial one, or we do not use the run. `--fmad=false` is there because the CPU builds turn contraction off; without it the probabilities would not match bit for bit.

The number the GPU has to beat is 2.62 s, not 82 s. Thirty-two MPI ranks on one node are already 31× serial. Hybrid does not improve on that. So the slide should not quote a speed-up against serial alone.

Lessons:

1. The hash RNG made the port small. There is no device state to keep consistent with the host.
2. Bit-exact results cost the fused multiply-add. That is the same choice the CPU builds already made.
3. Copies are cheap only because they happen twice, not once per step. The queue is the other limit: 4 jobs running and 8 submitted in total, so the three repetitions are three jobs, and the size sweep waits.

If the GPU queue never starts, the slide uses the OpenACC multicore row against the OpenMP row (both on 32 cores) and says the device run was not measured.

EuroHPC, one sentence from Sanad, read as written. Do not estimate the node-hours on this slide.
