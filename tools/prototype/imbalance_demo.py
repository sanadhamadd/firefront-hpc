"""How uneven would the work be if the grid were split over 16 ranks?

A cell only needs real work when it is burning, or when it is unburnt and has
a burning neighbour. Everything else is a cheap "nothing happens" check. This
script runs the NumPy prototype and counts those busy cells per block, for a
4x4 block split and for 16 horizontal strips.
"""
import argparse
import csv

import numpy as np

from fire_prototype import simulate, NEIGHBOURS


def busy_cells(state, burn_steps=3):
    burning = (state >= 1) & (state <= burn_steps)
    near = np.zeros_like(burning)
    padded = np.pad(burning, 1)
    n, m = burning.shape
    for dr, dc in NEIGHBOURS:
        near |= padded[1 + dr:1 + dr + n, 1 + dc:1 + dc + m]
    return burning | ((state == 0) & near)


def per_block(mask, rows, cols):
    n, m = mask.shape
    out = np.zeros((rows, cols))
    for i in range(rows):
        for j in range(cols):
            out[i, j] = mask[i * n // rows:(i + 1) * n // rows,
                             j * m // cols:(j + 1) * m // cols].sum()
    return out


def imbalance(counts):
    """max / mean of busy cells per rank (1.0 = perfectly even)."""
    mean = counts.mean()
    return counts.max() / mean if mean > 0 else 1.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--steps", type=int, default=140)
    ap.add_argument("--csv", default="imbalance.csv")
    args = ap.parse_args()

    rows = []
    snapshot = None
    for step, state, _ in simulate(args.size, args.size, args.steps, seed=3):
        mask = busy_cells(state)
        blocks = per_block(mask, 4, 4)
        strips = per_block(mask, 16, 1)
        rows.append((step, int(mask.sum()), imbalance(blocks), imbalance(strips)))
        if step == 100:
            snapshot = blocks
    with open(args.csv, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["step", "busy_cells", "imbalance_blocks_4x4", "imbalance_strips_16"])
        w.writerows(rows)
    np.save(args.csv.replace(".csv", "_blocks_step100.npy"), snapshot)
    print("wrote", args.csv)


if __name__ == "__main__":
    main()
