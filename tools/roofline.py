"""Upper bound on cell updates per second from the memory bandwidth (roofline).

Usage:
    python tools/roofline.py 66.8              # bandwidth in GB/s, bw_gbs from build/stream
    python tools/roofline.py 66.8 --bytes 7    # mark another model as the main one

If the kernel is limited by memory bandwidth, it cannot update more cells per
second than bandwidth / bytes moved per cell update. The script prints the bound
for all three byte counts and marks the chosen one (default 6).

Bytes per cell update, counted in src/sim.c (sim_step). Per cell the code reads its
state byte (uint8_t) and, for an unburnt cell, its fuel (float, 4 B); only when a
neighbour is burning does it also read its elevation (float, 4 B). It writes one
state byte. The eight neighbour state bytes (and neighbour elevations) sit in the
rows just above and below, which are still in cache from the previous rows.

    6 B  (default) an unburnt cell far from any fire: read state 1 + fuel 4, write 1.
         This is about 98 % of all updates in our runs. Counted like STREAM, without
         write-allocate, and compared with bw_gbs directly.
    7 B  the same with write-allocate: before the new state byte is written, the CPU
         reads its cache line, so the write costs 1 B more. STREAM's bw_gbs does not
         count that extra read either (3 x 8 B per triad element, but 4 x 8 B really
         move), so for a like-for-like bound the 7 B are compared with STREAM's real
         traffic, bw_gbs x 4/3.
   10 B  the older "every array is streamed" model: state 1 + fuel 4 + elevation 4,
         write 1, i.e. as if every cell were next to the fire (true for well under
         1 % of the cells). Measured runs exceed this bound, so it is too pessimistic.

Burning and burnt cells only read and write their state byte (2 B, 3 B with
write-allocate), so a run with a large burnt area moves even less.
"""
import argparse

# bytes per update -> (description, factor applied to bw_gbs)
MODELS = {
    6: ("far from the fire, no write-allocate (STREAM's counting)", 1.0),
    7: ("far from the fire, with write-allocate (vs STREAM real traffic = bw x 4/3)", 4.0 / 3.0),
    10: ("every array streamed (old model, too pessimistic)", 1.0),
}


def max_updates_per_s(bw_gbs, bytes_per_update):
    """Bandwidth in GB/s (1 GB = 1e9 bytes, as STREAM reports it) -> cell updates per second."""
    _, factor = MODELS[bytes_per_update]
    return bw_gbs * factor * 1e9 / bytes_per_update


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("bw_gbs", type=float, help="memory bandwidth in GB/s (bw_gbs from build/stream)")
    ap.add_argument("--bytes", type=int, choices=sorted(MODELS), default=6,
                    help="byte model to mark as the main bound (default 6)")
    args = ap.parse_args()
    if args.bw_gbs <= 0:
        ap.error("bandwidth must be positive")

    print(f"STREAM bandwidth {args.bw_gbs:g} GB/s")
    for b, (text, _) in MODELS.items():
        rate = max_updates_per_s(args.bw_gbs, b)
        mark = "  <- chosen" if b == args.bytes else ""
        print(f"{b:>3} B per update: max {rate:.3e} cell updates/s ({rate / 1e6:>7,.0f} MCUPS)  {text}{mark}")


if __name__ == "__main__":
    main()
