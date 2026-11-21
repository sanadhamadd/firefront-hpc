"""E5 table and figures: strips vs blocks, one node vs two nodes.

Usage:
    python tools/plot_e5.py results/tables/all.csv results/tables results/figures

Uses the MPI runs from slurm/e5_decomp.sbatch (files e5_decomp_*.out): 8192 x 8192,
400 steps, one thread per rank. Runs with the same decomposition, node count and rank
count are one point: the median over the repetitions, with min and max as error bars.

Speed-up is against the median serial E1 time for the same grid. The halo share is
t_halo / t_total, both the largest value over the ranks; t_halo includes the time a rank
waits for a slower neighbour, so it is the exposed communication, not pure transfer time.

Writes e5_summary.csv into the table folder and two PNGs into the figure folder:
e5_time_vs_ranks.png and e5_efficiency_halo.png.
"""
import argparse
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

NAVY = "#1F3A68"
TERRACOTTA = "#CF7A55"
GREY = "#6B6B6B"
GRID = "#E3E3E3"
COLOUR = {"strips": TERRACOTTA, "blocks": NAVY}
MARKER = {"strips": "s", "blocks": "o"}


def load(csv_path):
    df = pd.read_csv(csv_path, dtype={"commit": str, "checksum": str, "job_id": str})
    serial = df[(df.variant == "serial") & (df.nx == 8192)]
    if serial.empty:
        sys.exit("no serial 8192 x 8192 run (E1) in the CSV, needed for the speed-up")
    e5 = df[(df.variant == "mpi") & (df.nx == 8192) & df.file.str.startswith("e5_decomp_")].copy()
    if e5.empty:
        sys.exit("no E5 runs (e5_decomp_*.out) in the CSV")
    return serial.t_total.median(), e5


def summarise(t_serial, e5):
    keys = ["decomp", "nodes", "ranks"]
    g = e5.groupby(keys)
    s = g.agg(runs=("t_total", "size"),
              t_median=("t_total", "median"), t_min=("t_total", "min"), t_max=("t_total", "max"),
              t_halo=("t_halo", "median"), t_compute=("t_compute", "median"),
              t_reduce=("t_reduce", "median"), imbalance=("imbalance", "median"),
              cells_per_s=("cells_per_s", "median")).reset_index()
    s["speedup"] = t_serial / s.t_median
    s["efficiency"] = s.speedup / s.ranks
    s["halo_share"] = s.t_halo / s.t_median
    s["mcups"] = s.cells_per_s / 1e6
    return s.sort_values(keys)


def style(ax, ranks):
    ax.set_xscale("log", base=2)
    ax.set_xticks(ranks)
    ax.set_xticklabels([str(r) for r in ranks])
    ax.set_xlabel("MPI ranks (one core each)")
    ax.grid(True, color=GRID, linewidth=0.8)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)


def draw_series(ax, s, column, err=False):
    for decomp in ("strips", "blocks"):
        for nodes, ls, fill in ((1, "-", None), (2, "--", "none")):
            d = s[(s.decomp == decomp) & (s.nodes == nodes)]
            if d.empty:
                continue
            kw = dict(color=COLOUR[decomp], marker=MARKER[decomp], linestyle=ls,
                      markerfacecolor=fill or COLOUR[decomp], label=f"{decomp}, {nodes} node{'s' if nodes > 1 else ''}")
            if err:
                ax.errorbar(d.ranks, d[column], yerr=[d[column] - d.t_min, d.t_max - d[column]],
                            capsize=3, **kw)
            else:
                ax.plot(d.ranks, d[column], **kw)


def plot_time(s, t_serial, out):
    ranks = sorted(s.ranks.unique())
    fig, ax = plt.subplots(figsize=(6.4, 4.4))
    ax.plot(ranks, [t_serial / r for r in ranks], ":", color=GREY, label="ideal (serial / ranks)")
    draw_series(ax, s, "t_median", err=True)
    ax.set_yscale("log")
    ax.set_ylabel("wall time (s), median of 3")
    ax.set_title("E5: 8192², 400 steps, strips vs blocks")
    style(ax, ranks)
    ax.legend(fontsize=8, frameon=False)
    fig.tight_layout()
    fig.savefig(out, dpi=200)
    plt.close(fig)


def plot_efficiency_halo(s, out):
    ranks = sorted(s.ranks.unique())
    fig, (a, b) = plt.subplots(1, 2, figsize=(10, 4.2))
    draw_series(a, s, "efficiency")
    a.axhline(1.0, color=GREY, linestyle=":", linewidth=1)
    a.set_ylim(0, 1.15)
    a.set_ylabel("parallel efficiency (vs serial E1)")
    a.set_title("Efficiency")
    style(a, ranks)
    a.legend(fontsize=8, frameon=False, loc="lower left")
    s2 = s[s.ranks > 1].copy()
    s2["halo_pct"] = 100 * s2.halo_share
    draw_series(b, s2, "halo_pct")
    b.set_ylabel("t_halo / t_total (%)")
    b.set_title("Share of time in the halo exchange")
    style(b, ranks)
    fig.tight_layout()
    fig.savefig(out, dpi=200)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("csv")
    ap.add_argument("table_dir")
    ap.add_argument("figure_dir")
    args = ap.parse_args()

    t_serial, e5 = load(args.csv)
    s = summarise(t_serial, e5)
    Path(args.table_dir).mkdir(parents=True, exist_ok=True)
    Path(args.figure_dir).mkdir(parents=True, exist_ok=True)
    table = Path(args.table_dir) / "e5_summary.csv"
    s.round(4).to_csv(table, index=False)
    plot_time(s, t_serial, Path(args.figure_dir) / "e5_time_vs_ranks.png")
    plot_efficiency_halo(s, Path(args.figure_dir) / "e5_efficiency_halo.png")
    print(f"serial E1 median {t_serial:.2f} s; {len(e5)} E5 runs in {len(s)} configurations; wrote {table}")


if __name__ == "__main__":
    main()
