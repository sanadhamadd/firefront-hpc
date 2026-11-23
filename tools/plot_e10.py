"""E10 figures: GPU time and speed-up against the best one-node CPU result.

Usage:
    python tools/plot_e10.py results/raw results/tables results/figures

Reads RESULT lines whose variant is cuda, acc or accmc (the GPU jobs write
results/raw/gpu_*.out, gpu_sweep_*.out, acc_*.out and acc_mc_*.out). CPU baselines
come from results/tables/all.csv and results/tables/e3_final.csv. Writes
results/tables/e10_summary.csv and, when there is at least one run,
results/figures/e10_time.png and results/figures/e10_speedup.png.

Each point is the median of the repetitions. The bar or error bar runs from the
minimum to the maximum. Speed-up is the best one-node CPU time divided by the
GPU time. For the E1 problem that CPU time is the lowest of: serial, OpenMP at
32 threads (the e2_ jobs), MPI at 32 ranks on one node, and the best one-node
hybrid row in e3_final.csv. Other grid sizes use the OpenMP 32-thread size
sweep at humidity 0.2, when that row exists.

If there are no GPU logs yet, the script prints a message and exits 0.
"""

import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

NAVY = "#1F3A68"
TERRACOTTA = "#CF7A55"
TEAL = "#5A9BB0"
GREY = "#6B6B6B"
GRID = "#E3E3E3"
INK = "#1A1A1A"

GPU_VARIANTS = ("cuda", "acc", "accmc")
E1_REFERENCE = "0xb8683c550fa95bd6"


def parse_result_line(line):
    fields = {}
    for token in line.split()[1:]:
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


def read_gpu_logs(raw):
    rows = []
    for path in sorted(Path(raw).glob("*.out")):
        with open(path, errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line.startswith("RESULT "):
                    continue
                row = parse_result_line(line)
                if row.get("variant") not in GPU_VARIANTS:
                    continue
                row["file"] = path.name
                rows.append(row)
    return pd.DataFrame(rows)


def _median(series):
    vals = pd.to_numeric(series, errors="coerce").dropna()
    if vals.empty:
        return np.nan
    return float(vals.median())


def cpu_baselines(tables):
    """Named one-node CPU medians for the E1 problem, and OpenMP 32 by grid size."""
    all_path = Path(tables) / "all.csv"
    e3_path = Path(tables) / "e3_final.csv"
    info = {"e1": {}, "by_nx": {}}
    if not all_path.is_file():
        return info
    df = pd.read_csv(all_path, dtype={"commit": str, "checksum": str, "humidity": str, "file": str})
    for col in ("nx", "ny", "steps", "threads", "ranks", "nodes", "ignitions", "t_total"):
        if col in df:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    e1 = df[(df.nx == 8192) & (df.ny == 8192) & (df.steps == 400) & (df.ignitions == 16)]
    hum = e1.humidity.fillna("0.2").astype(str)
    e1 = e1[hum.isin(["0.2", "0.20"]) | e1.humidity.isna()]

    serial = e1[e1.variant == "serial"]
    if not serial.empty:
        info["e1"]["serial"] = _median(serial.t_total)

    omp = e1[(e1.variant == "omp") & (e1.threads == 32) & (e1.file.astype(str).str.startswith("e2_"))]
    if not omp.empty:
        info["e1"]["OpenMP 32"] = _median(omp.t_total)

    mpi = e1[(e1.variant == "mpi") & (e1.ranks == 32) & (e1.threads == 1) & (e1.nodes == 1)]
    if not mpi.empty and "decomp" in mpi:
        best = None
        for _, g in mpi.groupby(mpi.decomp.fillna("blocks")):
            med = _median(g.t_total)
            if best is None or med < best:
                best = med
        if best is not None:
            info["e1"]["MPI 32, 1 node"] = best

    sweep = df[(df.variant == "omp") & (df.threads == 32) & (df.steps == 400)]
    if "humidity" in sweep:
        h = sweep.humidity.fillna("0.2").astype(str)
        sweep = sweep[h.isin(["0.2", "0.20"])]
    for nx, g in sweep.groupby(sweep.nx):
        info["by_nx"][int(nx)] = _median(g.t_total)

    if e3_path.is_file():
        e3 = pd.read_csv(e3_path)
        one = e3[pd.to_numeric(e3.nodes, errors="coerce") == 1]
        if not one.empty:
            info["e1"]["hybrid, 1 node"] = float(pd.to_numeric(one.median_s, errors="coerce").min())
    return info


def best_cpu(info, nx, steps):
    if int(nx) == 8192 and int(steps) == 400 and info["e1"]:
        label = min(info["e1"], key=info["e1"].get)
        return info["e1"][label], label
    if int(nx) in info["by_nx"]:
        return info["by_nx"][int(nx)], f"OpenMP 32, {int(nx)}²"
    return np.nan, ""


def summarise(gpu, info):
    for col in ("nx", "ny", "steps", "ignitions", "t_kernel", "t_with_copies", "t_total"):
        if col not in gpu:
            gpu[col] = np.nan
        gpu[col] = pd.to_numeric(gpu[col], errors="coerce")
    keys = ["variant", "nx", "ny", "steps", "ignitions"]
    out = []
    for key, g in gpu.groupby(keys, dropna=False):
        variant, nx, ny, steps, ignitions = key
        cpu, label = best_cpu(info, nx, steps)
        def pack(col):
            vals = g[col].dropna()
            if vals.empty:
                return np.nan, np.nan, np.nan
            return float(vals.median()), float(vals.min()), float(vals.max())
        k_med, k_min, k_max = pack("t_kernel")
        c_med, c_min, c_max = pack("t_with_copies")
        checks = sorted(set(g.checksum.astype(str))) if "checksum" in g else []
        same = len(checks) == 1
        ref_ok = ""
        if int(nx) == 8192 and int(steps) == 400 and int(ignitions) == 16:
            ref_ok = "yes" if same and checks[0] == E1_REFERENCE else "no"
        elif same:
            ref_ok = "same across reps"
        out.append({
            "variant": variant,
            "nx": int(nx), "ny": int(ny), "steps": int(steps),
            "ignitions": int(ignitions) if pd.notna(ignitions) else "",
            "reps": int(len(g)),
            "checksum": checks[0] if same else "MIXED",
            "checksum_ok": ref_ok,
            "t_kernel_med": k_med, "t_kernel_min": k_min, "t_kernel_max": k_max,
            "t_with_copies_med": c_med, "t_with_copies_min": c_min, "t_with_copies_max": c_max,
            "cpu_best_s": cpu, "cpu_best_label": label,
            "speedup_kernel": cpu / k_med if k_med and cpu == cpu else np.nan,
            "speedup_with_copies": cpu / c_med if c_med and cpu == cpu else np.nan,
        })
    return pd.DataFrame(out).sort_values(["variant", "nx", "steps"]).reset_index(drop=True)


def _style(ax, ylabel):
    ax.set_ylabel(ylabel)
    ax.tick_params(colors=INK)
    ax.yaxis.label.set_color(INK)
    ax.xaxis.label.set_color(INK)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(axis="y", color=GRID)
    ax.set_axisbelow(True)


def plot_time(summary, info, path):
    if summary.nx.nunique() > 1:
        fig, ax = plt.subplots(figsize=(6.6, 4.2))
        colours = {"cuda": ("#2F6F4E", "#8FBF9F"), "acc": ("#7A5EA7", "#C4B3DE"), "accmc": ("#8C6A3D", "#D4C1A0")}
        for variant, g in summary.groupby("variant"):
            g = g.sort_values("nx")
            dark, light = colours.get(variant, (NAVY, TEAL))
            ax.errorbar(g.nx, g.t_kernel_med,
                        yerr=[g.t_kernel_med - g.t_kernel_min, g.t_kernel_max - g.t_kernel_med],
                        fmt="-o", color=dark, capsize=3, label=f"{variant} kernel")
            ax.errorbar(g.nx, g.t_with_copies_med,
                        yerr=[g.t_with_copies_med - g.t_with_copies_min, g.t_with_copies_max - g.t_with_copies_med],
                        fmt="--s", color=light, capsize=3, label=f"{variant} + copies")
        ax.set_xscale("log", base=2)
        ax.set_yscale("log")
        ax.set_xlabel("grid size")
        ax.legend(frameon=False, fontsize=8)
        ax.set_title("E10 time against grid size (median, bars min–max)", fontsize=10, color=INK)
        _style(ax, "time (s)")
        fig.tight_layout()
        fig.savefig(path, dpi=200)
        plt.close(fig)
        print("wrote", path, file=sys.stderr)
        return
    e1 = summary[(summary.nx == 8192) & (summary.steps == 400)]
    use = summary
    fig, ax = plt.subplots(figsize=(7.2, 4.2))
    labels, meds, los, his, colours = [], [], [], [], []
    if not e1.empty and info["e1"]:
        for name, colour in (("serial", GREY), ("OpenMP 32", NAVY),
                             ("MPI 32, 1 node", TERRACOTTA), ("hybrid, 1 node", TEAL)):
            if name in info["e1"]:
                labels.append(name)
                meds.append(info["e1"][name])
                los.append(0.0)
                his.append(0.0)
                colours.append(colour)
    palette = {"cuda": "#2F6F4E", "acc": "#7A5EA7", "accmc": "#8C6A3D"}
    for row in use.itertuples():
        for kind, med, lo, hi in (
            ("kernel", row.t_kernel_med, row.t_kernel_min, row.t_kernel_max),
            ("+ copies", row.t_with_copies_med, row.t_with_copies_min, row.t_with_copies_max),
        ):
            if med != med:
                continue
            labels.append(f"{row.variant} {kind}" + ("" if len(use) == 1 else f"\n{int(row.nx)}²"))
            meds.append(med)
            los.append(med - lo)
            his.append(hi - med)
            colours.append(palette.get(row.variant, GREY))
    x = np.arange(len(labels))
    ax.bar(x, meds, color=colours, zorder=2)
    ax.errorbar(x, meds, yerr=[los, his], fmt="none", ecolor=INK, elinewidth=1, capsize=3, zorder=3)
    ax.set_yscale("log")
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=8)
    nx = int(use.nx.iloc[0]) if use.nx.nunique() == 1 else None
    title = "E10 wall time, median of repetitions (bars min–max)"
    if nx:
        title = f"E10, {nx}², median of repetitions (bars min–max)"
    ax.set_title(title, fontsize=10, color=INK)
    _style(ax, "time (s)")
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)
    print("wrote", path, file=sys.stderr)


def plot_speedup(summary, path):
    fig, ax = plt.subplots(figsize=(6.6, 4.2))
    sizes = sorted(summary.nx.unique())
    if len(sizes) == 1:
        labels, meds, los, his, colours = [], [], [], [], []
        palette = {"cuda": "#2F6F4E", "acc": "#7A5EA7", "accmc": "#8C6A3D"}
        for row in summary.itertuples():
            for kind, med, lo_t, hi_t in (
                ("kernel", row.speedup_kernel, row.t_kernel_max, row.t_kernel_min),
                ("+ copies", row.speedup_with_copies, row.t_with_copies_max, row.t_with_copies_min),
            ):
                if med != med or row.cpu_best_s != row.cpu_best_s:
                    continue
                # a shorter GPU time is a higher speed-up, so min/max swap
                labels.append(f"{row.variant} {kind}")
                meds.append(med)
                los.append(med - row.cpu_best_s / lo_t)
                his.append(row.cpu_best_s / hi_t - med)
                colours.append(palette.get(row.variant, GREY))
        x = np.arange(len(labels))
        ax.bar(x, meds, color=colours, zorder=2)
        ax.errorbar(x, meds, yerr=np.vstack([los, his]), fmt="none", ecolor=INK,
                    elinewidth=1, capsize=3, zorder=3)
        ax.set_xticks(x)
        ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=8)
        who = summary.cpu_best_label.iloc[0]
        ax.set_title(f"Speed-up against {who}", fontsize=10, color=INK)
    else:
        for variant, g in summary.groupby("variant"):
            g = g.sort_values("nx")
            def yerr(med, slow, fast):
                # slow is the longer GPU time, so the lower speed-up
                lo = med - g.cpu_best_s / slow
                hi = g.cpu_best_s / fast - med
                return [lo.clip(lower=0), hi.clip(lower=0)]
            dark, light = {"cuda": ("#2F6F4E", "#8FBF9F"), "acc": ("#7A5EA7", "#C4B3DE"),
                           "accmc": ("#8C6A3D", "#D4C1A0")}.get(variant, (NAVY, TERRACOTTA))
            ax.errorbar(g.nx, g.speedup_kernel,
                        yerr=yerr(g.speedup_kernel, g.t_kernel_max, g.t_kernel_min),
                        fmt="-o", color=dark, capsize=3, label=f"{variant} kernel")
            ax.errorbar(g.nx, g.speedup_with_copies,
                        yerr=yerr(g.speedup_with_copies, g.t_with_copies_max, g.t_with_copies_min),
                        fmt="--s", color=light, capsize=3, label=f"{variant} + copies")
        ax.set_xscale("log", base=2)
        ax.set_xlabel("grid size")
        ax.legend(frameon=False, fontsize=8)
        ax.set_title("Speed-up against the best one-node CPU time at that size", fontsize=10, color=INK)
    ax.axhline(1.0, color=GREY, linewidth=1, linestyle=":")
    _style(ax, "speed-up (best CPU / GPU)")
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)
    print("wrote", path, file=sys.stderr)


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: python tools/plot_e10.py results/raw results/tables results/figures")
    raw, tables, figures = sys.argv[1:]
    gpu = read_gpu_logs(raw)
    if gpu.empty:
        print("no GPU RESULT lines in", raw, file=sys.stderr)
        print("submit slurm/gpu.sbatch (after gpu_build) and copy the logs back, then run this again",
              file=sys.stderr)
        return
    info = cpu_baselines(tables)
    summary = summarise(gpu, info)
    out_csv = Path(tables) / "e10_summary.csv"
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    summary.to_csv(out_csv, index=False)
    print("wrote", out_csv, file=sys.stderr)
    fig = Path(figures)
    fig.mkdir(parents=True, exist_ok=True)
    plot_time(summary, info, fig / "e10_time.png")
    if summary.cpu_best_s.notna().any():
        plot_speedup(summary, fig / "e10_speedup.png")
    else:
        print("no CPU baseline in", tables, "; speed-up figure skipped", file=sys.stderr)


if __name__ == "__main__":
    main()
