"""Upper bound on cell updates per second from the memory bandwidth (roofline).

Usage:
    python tools/roofline.py 100          # bandwidth in GB/s, e.g. bw_gbs from build/stream

If the kernel is limited by memory bandwidth, it cannot update more cells per
second than bandwidth / bytes moved per cell update.

Why 10 bytes per cell update (src/sim.c, sim_step):
    read   1 B  state byte of the cell (old grid)
    read   4 B  fuel (float)
    read   4 B  elevation (float)
    write  1 B  state byte of the cell (new grid)
    ---------
          10 B  (9 B read + 1 B written)
The eight neighbour state bytes are not counted: they sit in the rows just
above and below, which are still in cache from the previous rows.

Write-allocate is left out on both sides. Before a byte is written, most CPUs
first read its cache line from memory, so a write really costs a read as well.
STREAM does not count that read: its bw_gbs is 3 x 8 bytes per triad element
(2 reads + 1 write) divided by the time. To divide like by like, the cell
update is counted the same way, 9 B read + 1 B written, without the extra byte.
(This keeps the same counting rule, not the exact hardware traffic: the hidden
read is 1/4 of the triad's real traffic but only 1/11 of ours, so the true
bound is somewhat higher than this one. Try --bytes 8.25, i.e. 11 B against
bw_gbs x 4/3, for that case.)

10 B is the "every array is streamed" estimate. In the code, elevation is only
read for a cell that has a burning neighbour, and fuel only for unburnt cells,
so far from the fire fewer bytes move (about 6 B, or 2 B for burnt cells). The
real bound can therefore be higher; --bytes shows that case.
"""
import argparse

BYTES_PER_UPDATE = 10


def max_updates_per_s(bw_gbs, bytes_per_update=BYTES_PER_UPDATE):
    """Bandwidth in GB/s (1 GB = 1e9 bytes, as STREAM reports it) -> cell updates per second."""
    return bw_gbs * 1e9 / bytes_per_update


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("bw_gbs", type=float, help="memory bandwidth in GB/s (bw_gbs from build/stream)")
    ap.add_argument("--bytes", type=float, default=BYTES_PER_UPDATE,
                    help=f"bytes moved per cell update (default {BYTES_PER_UPDATE})")
    args = ap.parse_args()
    if args.bw_gbs <= 0 or args.bytes <= 0:
        ap.error("bandwidth and bytes must be positive")

    rate = max_updates_per_s(args.bw_gbs, args.bytes)
    print(f"bandwidth {args.bw_gbs:g} GB/s, {args.bytes:g} bytes per cell update")
    print(f"max cell updates per second: {rate:.3e} ({rate / 1e6:,.0f} MCUPS)")


if __name__ == "__main__":
    main()
