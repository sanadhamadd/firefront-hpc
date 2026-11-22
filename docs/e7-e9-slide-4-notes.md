# Slide 4 · MPI halo exchange across nodes

The editable slide shows completed E5 baseline data from
`results/tables/e5_summary.csv`. The chart uses the medians of three
blocking runs at 32 ranks × 1 thread, with blocks. Total loop and halo
time are plotted side by side because each is a rank maximum and the two
need not come from the same rank. The two-node allocation used 16 ranks
per node. Update the chart to the completed E7 before/after comparison
and revise the final line of the speaker notes once the SciTech data arrives.

## Speaker notes · about 50 seconds

At the same 32 MPI ranks, the blocking solver took 2.62 seconds on one node
and 4.56 seconds across two nodes. The halo exchange rose from 0.29 seconds
to 2.20 seconds. These timers include time spent waiting for neighbors, and
the two nodes communicated over TCP. That made halo exchange the first
place we looked for an improvement.

The overlap mode posts the row exchange and computes the interior while
those messages are in flight. It then finishes the row exchange, forwards
the corner values with the columns, and updates the boundary. Both modes
must pass the same checksum before we time them on a shared allocation.
The paired SciTech timings are pending. The comparison will tell us whether
the change saves time across the whole run.
