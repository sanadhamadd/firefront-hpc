"""E8 (tile skipping) table and figures from the CSV written by parse_logs.py.

Usage:
    python tools/parse_logs.py results/raw > results/tables/all.csv
    python tools/plot_e8.py results/tables/all.csv results/tables results/figures

Uses the runs from slurm/e8_skip_tiles.sbatch (files e8_skip_tiles_*.out: serial and
OpenMP) and slurm/e8_skip_tiles_mpi.sbatch (files e8_mpi_*.out). A run whose checksum is
not the E1 reference is left out with a warning. One configuration is (variant, nodes,
ranks, threads, skip_tiles); for each it reports the median over the repetitions with
min and max, the medians of the MPI phase timers and imbalance, and the share of tile
updates that were computed (active_tiles).

Writes:
    e8_summary.csv        one row per configuration
    e8_before_after.png   time without and with skipping (tile TILE), log scale
    e8_tile_size.png      most threads: speed-up against no skipping for each tile size
    e8_mpi_balance.png    MPI: compute imbalance and halo share of the run, before/after
"""
import argparse
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker
import pandas as pd

REFERENCE = "0xb8683c550fa95bd6"
TILE = 32                    # tile size of the before/after comparison (job default)
BEFORE = "#2A78C2"           # checked with the dataviz palette validator (light surface):
AFTER = "#CF7A55"            # CVD dE 19, normal-vision dE 27, both >= 3:1 contrast
INK = "#444444"
GRID = "#E3E3E3"
REF_LINE = "#9A9A9A"
KEYS = ["variant", "nodes", "ranks", "threads", "skip_tiles"]


def load(csv_path):
    df = pd.read_csv(csv_path, dtype=str)
    if "file" not in df or "skip_tiles" not in df:
        sys.exit("no E8 runs in the CSV (no skip_tiles column)")
    df = df[df.file.str.startswith("e8_")].copy()
    if df.empty:
        sys.exit("no E8 runs (e8_*.out) in the CSV")
    bad = df[df.checksum != REFERENCE]
    for _, row in bad.iterrows():
        print(f"warning: {row.file} has checksum {row.checksum}, left out", file=sys.stderr)
    df = df[df.checksum == REFERENCE]
    for col in ["nodes", "ranks", "threads", "skip_tiles"]:
        df[col] = pd.to_numeric(df[col]).astype(int)
    for col in ["t_total", "t_halo", "t_compute", "imbalance", "active_tiles"]:
        df[col] = pd.to_numeric(df[col])
    df["nodes"] = df.nodes.where(df.variant == "mpi", 1)
    return df


def summarise(df):
    g = df.groupby(KEYS)
    s = g.t_total.agg(reps="size", t_med="median", t_min="min", t_max="max")
    for col in ["t_halo", "t_compute", "imbalance", "active_tiles"]:
        s[col] = g[col].median()
    s = s.reset_index()
    s["halo_share"] = s.t_halo / s.t_med
    base = s[s.skip_tiles == 0].set_index(["variant", "nodes", "ranks", "threads"]).t_med
    s["speedup_vs_no_skip"] = [
        base.get((r.variant, r.nodes, r.ranks, r.threads), float("nan")) / r.t_med
        for r in s.itertuples()]
    return s


def label(row):
    if row.variant == "serial":
        return "serial"
    if row.variant == "omp":
        return f"{row.threads} threads"
    return f"{row.ranks} ranks\n{row.nodes} node" + ("s" if row.nodes > 1 else "")


def style(ax, ylabel):
    ax.set_ylabel(ylabel, color=INK)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(REF_LINE)
    ax.tick_params(colors=INK)


def pairs(s):
    """configurations that have both a no-skip run and a run with tile TILE"""
    before = s[s.skip_tiles == 0]
    after = s[s.skip_tiles == TILE]
    p = before.merge(after, on=["variant", "nodes", "ranks", "threads"], suffixes=("_b", "_a"))
    order = {"serial": 0, "omp": 1, "mpi": 2}
    p["o"] = p.variant.map(order)
    return p.sort_values(["o", "nodes", "ranks", "threads"]).reset_index(drop=True)


def bars(ax, p, col_b, col_a, lo_hi=True):
    x = range(len(p))
    w = 0.38
    for off, col, colour, name in ((-w / 2, col_b, BEFORE, "no skipping"),
                                   (w / 2, col_a, AFTER, f"--skip-tiles {TILE}")):
        xs = [i + off for i in x]
        ax.bar(xs, p[col], width=w - 0.04, color=colour, label=name, zorder=2)
        if lo_hi:
            suffix = col[-2:]
            lo = p[col] - p["t_min" + suffix]
            hi = p["t_max" + suffix] - p[col]
            ax.errorbar(xs, p[col], yerr=[lo, hi], fmt="none", ecolor=INK, elinewidth=1,
                        capsize=2, zorder=3)
    ax.set_xticks(list(x))
    ax.set_xticklabels([label(r) for r in p.itertuples()], fontsize=8)


def plot_before_after(p, path):
    """Dumbbell on a log axis (bar lengths would mean nothing on a log scale)."""
    fig, ax = plt.subplots(figsize=(6.4, 4.2))
    x = list(range(len(p)))
    ax.vlines(x, p.t_med_a, p.t_med_b, color=GRID, linewidth=3, zorder=1)
    for col, colour, name in (("_b", BEFORE, "no skipping"), ("_a", AFTER, f"--skip-tiles {TILE}")):
        ax.errorbar(x, p["t_med" + col], yerr=[p["t_med" + col] - p["t_min" + col], p["t_max" + col] - p["t_med" + col]],
                    fmt="o", markersize=8, color=colour, ecolor=INK, elinewidth=1, capsize=2,
                    markeredgecolor="white", markeredgewidth=1.5, label=name, zorder=3)
    for i, r in enumerate(p.itertuples()):          # speed-up next to each pair
        mid = (r.t_med_a * r.t_med_b) ** 0.5
        ax.annotate(f"{r.t_med_b / r.t_med_a:.0f}×", (i, mid), textcoords="offset points",
                    xytext=(8, 0), va="center", fontsize=8, color=INK)
    ax.set_yscale("log")
    ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v:g}"))
    ax.set_xticks(x)
    ax.set_xticklabels([label(r) for r in p.itertuples()], fontsize=8)
    ax.set_xlim(-0.5, len(p) - 0.3)
    style(ax, "wall time of timed steps (s), log scale")
    ax.legend(frameon=False, fontsize=8)
    ax.set_title("E8: skipping tiles without fire, 8192² grid (median of runs, bars min–max)",
                 fontsize=9, color=INK)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def plot_tile_size(s, path):
    omp = s[(s.variant == "omp") & (s.threads == s[s.variant == "omp"].threads.max())]
    curve = omp[omp.skip_tiles > 0].sort_values("skip_tiles")
    none = omp[omp.skip_tiles == 0]
    if curve.empty:
        return
    if none.empty:
        return
    t0 = none.t_med.iloc[0]
    fig, ax = plt.subplots(figsize=(6.0, 4.0))
    # speed-up against no skipping on the same threads; error bars from the min-max times
    sp, sp_lo, sp_hi = t0 / curve.t_med, t0 / curve.t_max, t0 / curve.t_min
    ax.errorbar(curve.skip_tiles, sp, yerr=[sp - sp_lo, sp_hi - sp], color=AFTER, marker="o",
                markersize=8, linewidth=2, capsize=2, ecolor=INK, elinewidth=1,
                markeredgecolor="white", markeredgewidth=1.5, zorder=3)
    for r, top in zip(curve.itertuples(), sp_hi):      # share of tile updates computed
        ax.annotate(f"{100 * r.active_tiles:.1f} % of tiles", (r.skip_tiles, top),
                    textcoords="offset points", xytext=(0, 8), ha="center", fontsize=7, color=INK,
                    bbox=dict(boxstyle="square,pad=0.15", facecolor="white", edgecolor="none"), zorder=4)
    ax.set_xscale("log", base=2)
    ax.set_xticks(list(curve.skip_tiles))
    ax.set_xticklabels([str(t) for t in curve.skip_tiles])
    ax.set_xlim(curve.skip_tiles.min() / 1.5, curve.skip_tiles.max() * 1.5)
    ax.set_ylim(0, float(sp_hi.max()) * 1.15)
    ax.set_xlabel("tile edge T (cells)", color=INK)
    style(ax, f"speed-up against no skipping ({t0:.2f} s)")
    ax.set_title(f"E8: tile size, {int(curve.threads.iloc[0])} threads, 8192² grid", fontsize=9, color=INK)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def plot_mpi_balance(p, path):
    m = p[p.variant == "mpi"].reset_index(drop=True)
    if m.empty:
        return
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(7.6, 3.8))
    bars(a1, m, "imbalance_b", "imbalance_a", lo_hi=False)
    a1.axhline(1.0, color=REF_LINE, linestyle="--", linewidth=1, zorder=1)
    style(a1, "compute imbalance (slowest / average rank)")
    a1.set_title("(a) load imbalance", fontsize=9, color=INK)
    m = m.assign(hs_b=100 * m.halo_share_b, hs_a=100 * m.halo_share_a)
    bars(a2, m, "hs_b", "hs_a", lo_hi=False)
    a2.set_ylim(0, 100)
    style(a2, "halo time / wall time (%)")
    a2.set_title("(b) share of the run in halo exchange", fontsize=9, color=INK)
    a2.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv")
    ap.add_argument("table_dir")
    ap.add_argument("figure_dir")
    args = ap.parse_args()
    df = load(args.csv)
    s = summarise(df)
    tables, figures = Path(args.table_dir), Path(args.figure_dir)
    tables.mkdir(parents=True, exist_ok=True)
    figures.mkdir(parents=True, exist_ok=True)
    s.to_csv(tables / "e8_summary.csv", index=False, float_format="%.4g")
    p = pairs(s)
    if not p.empty:
        plot_before_after(p, figures / "e8_before_after.png")
        plot_mpi_balance(p, figures / "e8_mpi_balance.png")
    plot_tile_size(s, figures / "e8_tile_size.png")
    print(f"{len(df)} E8 runs in {len(s)} configurations; wrote {tables / 'e8_summary.csv'} and figures in {figures}")


if __name__ == "__main__":
    main()
