"""Write Phase 3a tables and figures from checksum-verified hybrid logs."""
import argparse
from collections import defaultdict
import csv
from pathlib import Path
from statistics import median
import sys

from phase3a_results import read_runs
from submit_phase3a import planned_experiment

FIELDS = ("experiment", "nx", "ny", "steps", "nodes", "ranks", "threads",
          "decomp", "overlap", "humidity", "commit")


def summarize(runs):
    groups = defaultdict(dict)
    references = {}
    for run in runs:
        reference_key = tuple(run[field] for field in ("nx", "ny", "steps", "humidity", "commit"))
        if references.setdefault(reference_key, run["checksum"]) != run["checksum"]:
            raise ValueError(f"inconsistent checksums for {reference_key}")
        key = tuple(run[field] for field in FIELDS)
        previous = groups[key].setdefault(run["rep"], run)
        if previous["job"] != run["job"]:
            raise ValueError(f"duplicate repetition {run['rep']} in jobs "
                             f"{previous['job']} and {run['job']}")
    rows = []
    for key, reps in sorted(groups.items()):
        runs = [reps[rep] for rep in sorted(reps)]
        row = dict(zip(FIELDS, key))
        cores = row["ranks"] * row["threads"]
        cells = row["nx"] * row["ny"]
        times = [float(run["t_total"]) for run in runs]
        rates = [float(run["cells_per_s"]) / 1e6 for run in runs]
        row.update(cores=cores, cells=cells, cells_per_core=cells / cores, reps=len(runs),
                   jobs=" ".join(str(run["job"]) for run in runs),
                   median_s=median(times), min_s=min(times), max_s=max(times),
                   median_mcups=median(rates), min_mcups=min(rates), max_mcups=max(rates))
        if all("t_halo" in run for run in runs):
            halo = [float(run["t_halo"]) for run in runs]
            row.update(median_halo_s=median(halo), min_halo_s=min(halo), max_halo_s=max(halo))
        rows.append(row)

    for row in rows:
        peers = [peer for peer in rows if all(
            row[field] == peer[field]
            for field in ("experiment", "steps", "decomp", "overlap", "humidity", "commit"))]
        if row["experiment"] == "e3":
            same_work = [peer for peer in peers if all(row[field] == peer[field]
                         for field in ("nx", "ny", "cores"))]
            one_node = [peer for peer in same_work if peer["nodes"] == 1 and all(
                        row[field] == peer[field] for field in ("ranks", "threads"))]
            relative_to_one = inverse_ratio(one_node, row, "median_s")
            row["runtime_increase_pct_vs_one_node"] = (
                100 * (relative_to_one - 1) if relative_to_one is not None else None)
            peers = [peer for peer in same_work if row["nodes"] == peer["nodes"]
                     and peer["threads"] == 1]
            row["speedup_vs_mpi_only"] = ratio(peers, row, "median_s")
            relative = inverse_ratio(peers, row, "median_s")
            row["runtime_reduction_pct_vs_mpi_only"] = (
                100 * (1 - relative) if relative is not None else None)
        elif row["experiment"] == "e4":
            peers = [peer for peer in peers if peer["cores"] == 1
                     and peer["cells_per_core"] == row["cells_per_core"]]
            row["weak_efficiency"] = ratio(peers, row, "median_s")
        elif row["experiment"] == "e6":
            peers = [peer for peer in peers if all(row[field] == peer[field]
                     for field in ("nodes", "ranks", "threads")) and peer["cells"] == 2048**2]
            row["runtime_vs_s"] = inverse_ratio(peers, row, "median_s")
            row["throughput_vs_s"] = inverse_ratio(peers, row, "median_mcups")
    return rows


def ratio(baselines, row, field):
    return baselines[0][field] / row[field] if len(baselines) == 1 else None


def inverse_ratio(baselines, row, field):
    return row[field] / baselines[0][field] if len(baselines) == 1 else None


def plot(experiment, rows, path, plt, halo=False):
    metrics = [("halo_s", "Halo exchange (s)")] if halo else [("s", "Runtime (s)")]
    if experiment == "e6":
        metrics.append(("mcups", "Million cell updates/s"))
    series = defaultdict(list)
    for row in rows:
        key = (row["commit"], row["steps"], row["decomp"], row["overlap"], row["humidity"])
        if experiment == "e3":
            key += (f"{row['nx']}×{row['ny']}", f"{row['cores']} cores", f"{row['nodes']} node(s)")
        elif experiment == "e6":
            key += (layout(row),)
        else:
            key += (f"{row['cells_per_core']:g} cells/core",)
        series[key].append(row)

    def category(row):
        if experiment == "e3":
            return row["ranks"], row["threads"]
        if experiment == "e4":
            return row["cores"], row["nodes"], row["ranks"], row["threads"], row["nx"], row["ny"]
        return row["nx"], row["ny"]

    def label(key):
        if experiment == "e3":
            return f"{key[0]}×{key[1]}"
        if experiment == "e4":
            cores, nodes, ranks, threads, nx, ny = key
            return f"{cores} cores\n{nx}×{ny}\n{ranks}×{threads}, {nodes} node(s)"
        return f"{key[0]}×{key[1]}"

    categories = sorted({category(row) for row in rows})
    fig, axes = plt.subplots(len(metrics), 1, figsize=(9, 4 * len(metrics)), squeeze=False)
    for axis, (metric, ylabel) in zip(axes[:, 0], metrics):
        for index, (key, group) in enumerate(sorted(series.items())):
            group = sorted(group, key=category)
            offset = (index - (len(series) - 1) / 2) * 0.6 / len(series)
            x = [categories.index(category(row)) + offset for row in group]
            y = [row[f"median_{metric}"] for row in group]
            bars = [[value - row[f"min_{metric}"] for row, value in zip(group, y)],
                    [row[f"max_{metric}"] - value for row, value in zip(group, y)]]
            commit, steps, decomp, overlap, humidity, *details = key
            name = ", ".join([*details, f"{commit}, {steps} steps, {decomp}, "
                              f"overlap {overlap}, humidity {humidity}"])
            points = axis.errorbar(x, y, yerr=bars, fmt="o" if experiment == "e3" else "o-",
                                   capsize=4, label=name)
            if experiment == "e4":
                baseline = [row["median_s"] for row in group if row["cores"] == 1]
                if len(baseline) == 1:
                    axis.axhline(baseline[0], linestyle="--", alpha=0.65,
                                 color=points.lines[0].get_color(), label="Ideal weak scaling")
        axis.set_ylabel(f"Median {ylabel.lower()}")
        axis.set_xticks(range(len(categories)))
        axis.set_xticklabels([label(key) for key in categories])
        axis.grid(axis="y", alpha=0.25)
        axis.legend(fontsize="small")
    axes[-1, 0].set_xlabel({"e3": "MPI ranks × OpenMP threads", "e4": "Allocation",
                            "e6": "Grid resolution"}[experiment])
    fig.suptitle({"e3": "E3 · Hybrid splits", "e4": "E4 · Weak scaling",
                  "e6": "E6 · Resolution scaling"}[experiment])
    fig.text(0.5, 0.01, "Error bars show the minimum and maximum across repetitions",
             ha="center", fontsize=9)
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    fig.savefig(path, dpi=180)
    plt.close(fig)


def report_plot(experiment, rows, output, plt):
    """Draw the two panels used in the report at a common print size."""
    fig, (left, right) = plt.subplots(1, 2, figsize=(7.2, 2.8), layout="constrained")
    colors = ("#0072B2", "#D55E00")

    def draw(axis, x, group, metric, label, color, marker):
        values = [row[f"median_{metric}"] for row in group]
        bounds = [[value - row[f"min_{metric}"] for row, value in zip(group, values)],
                  [row[f"max_{metric}"] - value for row, value in zip(group, values)]]
        axis.errorbar(x, values, yerr=bounds, label=label, color=color, marker=marker,
                      linestyle="-", linewidth=1.4, markersize=4, capsize=3)

    if experiment == "e3":
        splits = sorted({(row["ranks"], row["threads"]) for row in rows})
        for nodes, offset, color, marker in zip((1, 2), (-0.06, 0.06), colors, ("o", "s")):
            group = sorted((row for row in rows if row["nodes"] == nodes),
                           key=lambda row: (row["ranks"], row["threads"]))
            x = [splits.index((row["ranks"], row["threads"])) + offset for row in group]
            label = "1 node" if nodes == 1 else "2 nodes"
            draw(left, x, group, "s", label, color, marker)
            draw(right, x, group, "halo_s", label, color, marker)
        for axis in (left, right):
            axis.set_xticks(range(len(splits)), [f"{r}×{t}" for r, t in splits])
            axis.set_xlabel("MPI ranks × OpenMP threads")
        left.legend(loc="upper right", frameon=False, fontsize=8)
        right.set_ylabel("Halo exchange time (s)")
        right.set_ylim(bottom=0)
    else:
        group = sorted(rows, key=lambda row: row["cores"])
        cores = [row["cores"] for row in group]
        baseline = group[0]["median_s"]
        draw(left, cores, group, "s", "Measured", colors[0], "o")
        left.axhline(baseline, color="#666666", linestyle="--", linewidth=1, label="Ideal")
        left.legend(frameon=False, fontsize=8)
        right.plot(cores, [100 * row["weak_efficiency"] for row in group],
                   color=colors[0], marker="o", linewidth=1.4, markersize=4)
        right.axhline(100, color="#666666", linestyle="--", linewidth=1)
        right.set_ylabel("Weak-scaling efficiency (%)")
        right.set_ylim(0, 110)
        for axis in (left, right):
            axis.set_xscale("log", base=2)
            axis.set_xticks(cores, [str(core) for core in cores])
            axis.set_xlabel("Physical cores")
    left.set_ylabel("Runtime (s)")
    for letter, axis in zip(("a", "b"), (left, right)):
        axis.set_title(f"({letter})", loc="left", fontsize=9)
        axis.grid(axis="y", color="#dddddd", linewidth=0.6)
        axis.spines[["top", "right"]].set_visible(False)
        axis.tick_params(labelsize=8)
    for extension in ("pdf", "png"):
        fig.savefig(output / f"{experiment}_report.{extension}", dpi=300)
    plt.close(fig)


def layout(row):
    return f"{row['ranks']}×{row['threads']}, {row['nodes']} node(s)"


def phase3a_runs(directory):
    for row in read_runs(directory, include_legacy=True):
        row["experiment"] = row["experiment"] or planned_experiment(row)
        if row["experiment"] in {"e3", "e4", "e6"}:
            yield row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", type=Path)
    parser.add_argument("output", type=Path, help="new directory for tables and figures")
    parser.add_argument("--tables-only", action="store_true")
    parser.add_argument("--report", action="store_true", help="export final E3/E4 report panels")
    parser.add_argument("--e3-cores", type=int, help="only plot E3 runs at this core count")
    args = parser.parse_args()
    if not args.logs.is_dir():
        parser.error(f"log directory does not exist: {args.logs}")
    try:
        runs = list(phase3a_runs(args.logs))
        if args.e3_cores is not None:
            runs = [r for r in runs if r["experiment"] == "e3"
                    and r["ranks"] * r["threads"] == args.e3_cores]
        if args.report:
            runs = [r for r in runs if r["experiment"] == "e4" or
                    (r["experiment"] == "e3" and r["ranks"] * r["threads"] == 32)]
        rows = summarize(runs)
        if not rows:
            raise ValueError("no verified Phase 3a logs")
        if not args.tables_only:
            import matplotlib
            matplotlib.use("Agg")
            import matplotlib.pyplot as plt
        args.output.mkdir()
        for experiment in ("e3", "e4", "e6"):
            selected = [row for row in rows if row["experiment"] == experiment]
            if not selected:
                continue
            with (args.output / f"{experiment}.csv").open("x", newline="") as file:
                writer = csv.DictWriter(file, fieldnames=list(dict.fromkeys(k for row in selected for k in row)), lineterminator="\n")
                writer.writeheader()
                writer.writerows(selected)
            if experiment == "e3" or args.report:
                fields = (*FIELDS, "nodelist", "job", "rep", "t_total", "cells_per_s",
                          "checksum", "t_halo", "source")
                with (args.output / f"{experiment}_runs.csv").open("x", newline="") as file:
                    writer = csv.DictWriter(file, fieldnames=fields, extrasaction="ignore",
                                            lineterminator="\n")
                    writer.writeheader()
                    writer.writerows(sorted(
                        (run for run in runs if run["experiment"] == experiment),
                        key=lambda run: (run["nodes"], run["ranks"], run["threads"], run["rep"])))
            if not args.tables_only and args.report:
                report_plot(experiment, selected, args.output, plt)
            elif not args.tables_only:
                plot(experiment, selected, args.output / f"{experiment}.png", plt)
                if experiment == "e3" and all("median_halo_s" in row for row in selected):
                    plot(experiment, selected, args.output / "e3_halo.png", plt, halo=True)
    except (ValueError, OSError, ImportError, KeyError) as exc:
        sys.exit(str(exc))


if __name__ == "__main__":
    main()
