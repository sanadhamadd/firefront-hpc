"""Make the scaling figures from the CSV written by parse_logs.py.

Usage:
    python tools/make_plots.py results/tables/all.csv results/figures

Runs with the same variant, nx, humidity and cores are one point: the median over the
repetitions, with min and max as error bars. Cores are physical cores, taken
from the places field of the RESULT line: ranks x threads for places=cores (one
thread per core), ranks x threads / 2 for places=threads (two threads per core
on its hyper-threads). Runs with places=threads are drawn as a separate star
marker, not as part of the scaling line; their efficiency is per physical core.
Writes four PNGs: wall time, speed-up, parallel efficiency and MCUPS, each
against cores, from all runs except the size sweep. If the logs contain the grid size sweep (files size_sweep_*.out from
slurm/size_sweep.sbatch), a fifth PNG shows MCUPS against grid size, one line per
humidity, with the memory limit at 6 bytes per update from the 32-core STREAM runs.

Speed-up is T(1) / T(p). T(1) is the median serial time for the same nx; if
there is no serial run for that nx, the variant's own 1-core run is used, and
if that is missing too the series is left out of the speed-up and efficiency
plots (a message says so).

Humidity separates runs that do different work per cell (e.g. the two passes of
slurm/size_sweep.sbatch). Logs from before the humidity field existed all used the
default, 0.2, so a missing value counts as 0.2. When the data has more than one
humidity, the legend shows it (H=...).
"""
import argparse
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.lines import Line2D
from matplotlib.ticker import FuncFormatter, LogLocator

NAVY = "#1F3A68"
TERRACOTTA = "#CF7A55"      # pastel, still 3:1 contrast on white
TEAL = "#5A9BB0"            # pastel, still 3:1 contrast on white
GREY = "#6B6B6B"
GRID = "#E3E3E3"

# fixed colour and marker per variant, so a variant looks the same in every figure
VARIANT_COLOUR = {"omp": NAVY, "mpi": TERRACOTTA, "hybrid": TEAL, "serial": GREY}
VARIANT_MARKER = {"omp": "o", "mpi": "s", "hybrid": "^", "serial": "D"}
OTHER_MARKERS = ["v", "P", "X", "h"]
# largest grid solid, smaller grids dashed and dotted
LINESTYLES = ["-", "--", ":", "-."]
SERIES = ["variant", "nx", "humidity"]   # one line per combination
DEFAULT_HUMIDITY = "0.2"                 # logs before the humidity field all used it


def load(csv_path):
    # identifiers stay text: a commit like 610e539 would otherwise be read as the number 610e539
    # humidity stays text too, so 0.2 groups as printed and is not split by float rounding
    df = pd.read_csv(csv_path, dtype={"commit": str, "checksum": str, "job_id": str, "humidity": str})
    if "humidity" not in df:
        df["humidity"] = DEFAULT_HUMIDITY
    df["humidity"] = df["humidity"].fillna(DEFAULT_HUMIDITY)
    for col in ("ranks", "threads"):
        if col not in df:
            df[col] = 1
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(1).astype(int)
    for col in ("t_total", "cells_per_s", "nx", "steps"):
        df[col] = pd.to_numeric(df.get(col), errors="coerce")
    df = df.dropna(subset=["t_total", "nx"])
    df["nx"] = df["nx"].astype(int)
    places = df["places"] if "places" in df else pd.Series("", index=df.index)
    df["ht"] = places.fillna("").astype(str) == "threads"   # two threads per physical core
    df["cores"] = df["ranks"] * df["threads"] // df["ht"].map({True: 2, False: 1})
    df["mcups"] = df["cells_per_s"] / 1e6
    return df


def summarise(df):
    """One row per (variant, nx, humidity, cores, ht): median, min and max of time and MCUPS."""
    keys = SERIES + ["cores", "ht"]
    for key, g in df.groupby(keys):
        for col in ("ny", "steps", "ignitions"):
            if col in g and g[col].nunique() > 1:
                print(f"warning: {key} mixes runs with different {col}: "
                      f"{sorted(g[col].dropna().unique())}", file=sys.stderr)
    s = df.groupby(keys).agg(
        t_med=("t_total", "median"), t_min=("t_total", "min"), t_max=("t_total", "max"),
        m_med=("mcups", "median"), m_min=("mcups", "min"), m_max=("mcups", "max"),
        reps=("t_total", "size"),
    ).reset_index()
    return s.sort_values(keys)


def add_speedup(s):
    """Speed-up and efficiency columns; error bars come from the min and max times."""
    s = s.copy()
    for col in ("sp_med", "sp_lo", "sp_hi"):
        s[col] = float("nan")
    for (variant, nx, hum), g in s.groupby(SERIES):
        serial = s[(s.variant == "serial") & (s.nx == nx) & (s.humidity == hum) & (s.cores == 1) & ~s.ht]
        own = g[(g.cores == 1) & ~g.ht]
        if len(serial):
            t1, base = serial.t_med.iloc[0], "serial"
        elif len(own):
            t1, base = own.t_med.iloc[0], f"{variant} on 1 core"
        else:
            print(f"note: no 1-core run for {variant} nx={nx} humidity={hum}, left out of speed-up",
                  file=sys.stderr)
            continue
        if variant != "serial":
            print(f"speed-up of {variant} nx={nx} humidity={hum} is relative to {base}", file=sys.stderr)
        idx = g.index
        s.loc[idx, "sp_med"] = t1 / s.loc[idx, "t_med"]
        s.loc[idx, "sp_lo"] = t1 / s.loc[idx, "t_max"]
        s.loc[idx, "sp_hi"] = t1 / s.loc[idx, "t_min"]
    for a, b in (("eff_med", "sp_med"), ("eff_lo", "sp_lo"), ("eff_hi", "sp_hi")):
        s[a] = s[b] / s["cores"]
    return s


def series_style(s):
    """Colour and marker by variant, line style by grid size and humidity, so identity never
    relies on colour alone."""
    sizes = sorted({(nx, hum) for nx, hum in zip(s.nx, s.humidity)}, key=lambda t: (-t[0], t[1]))
    others = sorted(v for v in s.variant.unique() if v not in VARIANT_MARKER)
    several_hum = s.humidity.nunique() > 1
    styles = {}
    for variant, nx, hum in s.groupby(SERIES).groups:
        marker = VARIANT_MARKER.get(variant)
        if marker is None:
            marker = OTHER_MARKERS[others.index(variant) % len(OTHER_MARKERS)]
        styles[(variant, nx, hum)] = dict(
            color=VARIANT_COLOUR.get(variant, GREY),
            marker=marker,
            linestyle=LINESTYLES[sizes.index((nx, hum)) % len(LINESTYLES)],
            label=f"{variant}, {nx}²" + (f", H={hum}" if several_hum else ""),
        )
    return styles


def new_axes(cores, ylabel):
    fig, ax = plt.subplots(figsize=(6.0, 4.0))
    ax.set_xscale("log", base=2)
    ax.set_xticks(cores)
    ax.set_xticklabels([str(c) for c in cores])
    ax.minorticks_off()
    ax.set_xlabel("physical cores")
    ax.set_ylabel(ylabel)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color("#9A9A9A")
    ax.tick_params(colors="#444444")
    return fig, ax


def plot_metric(s, styles, med, lo, hi, ylabel, path, ideal=None, logy=False, ylim=None):
    cores = sorted(s.cores.unique())
    fig, ax = new_axes(cores, ylabel)
    if ideal == "linear":
        ax.plot(cores, cores, color="#B5B5B5", linewidth=1.2, linestyle="--", label="ideal", zorder=1)
    elif ideal == "one":
        ax.axhline(1.0, color="#B5B5B5", linewidth=1.2, linestyle="--", label="ideal", zorder=1)
    handles, star_handles = [], []
    if ideal:
        handles.append(Line2D([], [], color="#B5B5B5", linewidth=1.2, linestyle="--", label="ideal"))
    for key, g_all in s.groupby(SERIES):
        g_all = g_all.dropna(subset=[med])
        st = styles[key]
        # hyper-thread runs: a separate open star at their number of physical cores
        h = g_all[g_all.ht]
        if not h.empty:
            ax.errorbar(h.cores, h[med], yerr=[h[med] - h[lo], h[hi] - h[med]], color=st["color"],
                        marker="*", linestyle="none", markersize=12, markerfacecolor="white",
                        markeredgewidth=1.5, capsize=3, elinewidth=1.2, zorder=4)
            star_handles.append(Line2D([], [], color=st["color"], marker="*", linestyle="none",
                                  markersize=12, markerfacecolor="white", markeredgewidth=1.5,
                                  label=f"{st['label']}, 2 threads per core"))
        g = g_all[~g_all.ht]
        if g.empty:
            continue
        yerr = [g[med] - g[lo], g[hi] - g[med]]
        ax.errorbar(g.cores, g[med], yerr=yerr, color=st["color"], marker=st["marker"],
                    linestyle=st["linestyle"] if len(g) > 1 else "none",
                    linewidth=2, markersize=7, markeredgecolor="white", markeredgewidth=1.2,
                    capsize=3, elinewidth=1.2, zorder=3)
        # legend entry without the error bar caps
        handles.append(Line2D([], [], color=st["color"], marker=st["marker"],
                              linestyle=st["linestyle"] if len(g) > 1 else "none",
                              linewidth=2, markersize=7, markeredgecolor="white",
                              label=st["label"]))
    if logy:
        ax.set_yscale("log")
        ax.yaxis.set_major_locator(LogLocator(base=10, subs=(1, 2, 5)))
        ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:g}"))
        ax.yaxis.set_minor_locator(LogLocator(base=10, subs="auto"))
        ax.yaxis.set_minor_formatter(FuncFormatter(lambda v, _: ""))
    if ylim:
        ax.set_ylim(*ylim)
    handles += star_handles   # stars after the lines in the legend
    if len(handles) >= 2:
        ax.legend(handles=handles, frameon=False, fontsize=9)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)
    print("wrote", path, file=sys.stderr)


def plot_size_sweep(csv_path, path):
    """MCUPS against grid size for the size sweep, one line per humidity (median, min-max).

    Only the sweep's own runs are used, so every point comes from the same cores. The
    grey line is the memory limit: median 32-core STREAM bandwidth / 6 bytes per update."""
    raw = pd.read_csv(csv_path, dtype={"commit": str, "checksum": str, "job_id": str, "humidity": str})
    if "file" not in raw:
        return
    sw = load(csv_path)
    sw = sw[sw.file.astype(str).str.startswith("size_sweep_") & ~sw.ht]
    if sw.nx.nunique() < 2:
        return
    sizes = sorted(sw.nx.unique())
    fig, ax = new_axes(sizes, "MCUPS (million cell updates / s)")
    ax.set_xticklabels([f"{n}²" for n in sizes])
    ax.set_xlabel(f"grid size ({int(sw.cores.median())} physical cores)")

    handles = []
    stream = raw[(raw.get("variant") == "stream") & (raw.get("places") == "cores")]
    stream = stream[pd.to_numeric(stream.threads, errors="coerce") == int(sw.cores.median())]
    if not stream.empty:
        limit = pd.to_numeric(stream.bw_gbs).median() * 1e9 / 6 / 1e6
        ax.axhline(limit, color="#B5B5B5", linewidth=1.2, linestyle="--", zorder=1)
        handles.append(Line2D([], [], color="#B5B5B5", linewidth=1.2, linestyle="--",
                              label=f"memory limit, 6 B per update ({limit:,.0f})"))
    passes = [("0.2", NAVY, "o", "-", "default (humidity 0.2)"),
              ("1", TERRACOTTA, "s", "--", "humidity 1, no spread")]
    for hum, colour, marker, ls, label in passes:
        g = sw[sw.humidity == hum].groupby("nx").mcups.agg(["median", "min", "max"])
        if g.empty:
            continue
        ax.errorbar(g.index, g["median"], yerr=[g["median"] - g["min"], g["max"] - g["median"]],
                    color=colour, marker=marker, linestyle=ls, linewidth=2, markersize=7,
                    markeredgecolor="white", markeredgewidth=1.2, capsize=3, elinewidth=1.2, zorder=3)
        handles.append(Line2D([], [], color=colour, marker=marker, linestyle=ls, linewidth=2,
                              markersize=7, markeredgecolor="white", label=label))
    top = max(sw.mcups.max(), limit if not stream.empty else 0)
    ax.set_ylim(0, top * 1.15)
    ax.legend(handles=handles, frameon=False, fontsize=9, loc="lower right")
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)
    print("wrote", path, file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("csv", help="CSV from parse_logs.py")
    ap.add_argument("outdir", help="folder for the PNG files")
    args = ap.parse_args()

    df = load(args.csv)
    if df.empty:
        sys.exit("no runs with t_total in " + args.csv)
    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)

    # the size sweep has its own figure: all its runs use 32 cores on other cores of the
    # node than E2, so it is kept out of the core-scaling figures
    if "file" in df:
        df = df[~df.file.astype(str).str.startswith("size_sweep_")]
    s = add_speedup(summarise(df))
    styles = series_style(s)
    no_serial = s[s.variant != "serial"]   # serial is the reference, not a curve

    plot_metric(s, styles, "t_med", "t_min", "t_max", "wall time of timed steps (s)",
                out / "time_vs_cores.png", logy=True)
    plot_metric(no_serial, styles, "sp_med", "sp_lo", "sp_hi", "speed-up T(1) / T(p)",
                out / "speedup_vs_cores.png", ideal="linear")
    top = max(1.1, float(no_serial.eff_hi.max()) * 1.05) if no_serial.eff_hi.notna().any() else 1.1
    plot_metric(no_serial, styles, "eff_med", "eff_lo", "eff_hi", "parallel efficiency",
                out / "efficiency_vs_cores.png", ideal="one", ylim=(0, top))
    plot_metric(s, styles, "m_med", "m_min", "m_max", "MCUPS (million cell updates / s)",
                out / "mcups_vs_cores.png")
    plot_size_sweep(args.csv, out / "mcups_vs_grid_size.png")


if __name__ == "__main__":
    main()
