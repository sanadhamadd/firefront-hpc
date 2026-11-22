"""Summarize checksum-verified, paired E7 Slurm jobs and render report figures."""

import argparse
from collections import defaultdict
import csv
from math import isfinite
from pathlib import Path
from statistics import median
import sys

from parse_logs import job_id_from_name, parse_result_line


REFERENCE = "0xb8683c550fa95bd6"
MATCH = ("variant", "nx", "ny", "steps", "seed", "ignitions", "humidity",
         "commit", "compiler", "nodes", "ranks", "threads", "places", "decomp", "px", "py")
TIMERS = ("t_halo", "t_compute", "t_reduce")
OVERLAP_TIMERS = ("t_post", "t_wait", "t_interior", "t_boundary")
TIMER_TOLERANCE = 0.00011  # RESULT timers are independently rounded to 0.0001 s.


def read_pairs(paths):
    for path in paths:
        lines = path.read_text(errors="replace").splitlines()
        if not lines or lines[-1] != "PAIR COMPLETE":
            print(f"Skipping incomplete job {path.name}", file=sys.stderr)
            continue
        meta, = [parse_result_line(line) for line in lines if line.startswith("PAIR ")
                 and line != "PAIR COMPLETE"]
        if meta["profile"] != "none":
            continue
        if f"VERIFIED checksum={REFERENCE}" not in lines:
            raise ValueError(f"{path.name}: missing untimed verification")
        rows = [parse_result_line(line) for line in lines if line.startswith("RESULT ")]
        if len(rows) != 2 or {r["overlap"] for r in rows} != {"0", "1"}:
            raise ValueError(f"{path.name}: expected exactly one pair")
        baseline, overlap = sorted(rows, key=lambda r: r["overlap"])
        if any(baseline[key] != overlap[key] for key in MATCH):
            raise ValueError(f"{path.name}: inconsistent pair configuration")
        expected = {"variant": "mpi", "nx": "8192", "ny": "8192", "steps": "400",
                    "seed": "42", "ignitions": "16", "humidity": "0.2", "commit": meta["commit"]}
        for row in (baseline, overlap):
            if row["checksum"] != REFERENCE or any(row[k] != v for k, v in expected.items()):
                raise ValueError(f"{path.name}: unexpected reference workload or checksum")
            total = float(row["t_total"])
            keys = TIMERS + (OVERLAP_TIMERS if row is overlap else ())
            values = [float(row[k]) for k in keys] + [float(row["imbalance"])]
            if not isfinite(total) or total <= 0 or any(not isfinite(v) for v in values):
                raise ValueError(f"{path.name}: invalid timing data")
            if any(not 0 <= float(row[k]) <= total + TIMER_TOLERANCE for k in keys) or values[-1] < 1:
                raise ValueError(f"{path.name}: timing or compute imbalance out of range")
            if row is overlap:
                for key, left, right in (("t_halo", "t_post", "t_wait"),
                                         ("t_compute", "t_interior", "t_boundary")):
                    whole, a, b = (float(row[k]) for k in (key, left, right))
                    if not max(a, b) - TIMER_TOLERANCE <= whole <= a + b + TIMER_TOLERANCE:
                        raise ValueError(f"{path.name}: inconsistent {key} component maxima")
            row.update(meta, job_id=job_id_from_name(path.name))
        yield baseline, overlap


def summarize(pairs):
    configs = defaultdict(dict)
    signature = None
    for baseline, overlap in pairs:
        identity = tuple(baseline[k] for k in ("binary_sha", "commit", "compiler", "transport"))
        if signature is not None and signature != identity:
            raise ValueError("Mixed builds or transports. Select logs from a single campaign.")
        signature = identity
        config = tuple(int(baseline[k]) for k in ("nodes", "ranks", "threads")) + (
            baseline["decomp"], baseline["allocation"],
        )
        rep = int(baseline["rep"])
        if rep in configs[config]:
            raise ValueError(f"Duplicate repetition {rep} for {config}. Select one job per repetition.")
        configs[config][rep] = (baseline, overlap)
    for config, repeats in sorted(configs.items()):
        nodes, ranks, threads, decomp, allocation = config
        summary = dict(nodes=nodes, ranks=ranks, threads=threads, decomp=decomp,
                       allocation=allocation, pairs=len(repeats))
        for mode, index in (("blocking", 0), ("overlap", 1)):
            runs = [pair[index] for pair in repeats.values()]
            totals = [float(r["t_total"]) for r in runs]
            summary.update({f"{mode}_median": median(totals), f"{mode}_min": min(totals),
                            f"{mode}_max": max(totals)})
            metrics = TIMERS + ("imbalance",) + (OVERLAP_TIMERS if index else ())
            summary.update({f"{mode}_{key}": median(float(r[key]) for r in runs) for key in metrics})
        before, after = (summary[f"{mode}_median"] for mode in ("blocking", "overlap"))
        summary["optimization_speedup"] = before / after
        summary["improvement_pct"] = 100 * (before - after) / before
        yield summary


def write_csv(path, rows):
    columns = list(dict.fromkeys(key for row in rows for key in row))
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


def plot(summary, out):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    x = list(range(len(summary)))
    labels = [f'{r["nodes"]}N · {r["ranks"]}R × {r["threads"]}T\n{r["decomp"]}\n{r["allocation"]}'
              for r in summary]
    specs = (
        ("runtime", "Wall-clock time (s)",
         (("blocking_median", "Blocking", "blocking"), ("overlap_median", "Overlap", "overlap"))),
        ("speedup", "Optimization speedup (×)",
         (("optimization_speedup", "Blocking / overlap", None),)),
        ("communication", "MPI call time (s)",
         (("blocking_t_halo", "Blocking exchange", None),
          ("overlap_t_wait", "Overlap wait only", None),
          ("overlap_t_halo", "Overlap post + wait", None))),
        ("imbalance", "Compute imbalance (max / mean)",
         (("blocking_imbalance", "Blocking", None), ("overlap_imbalance", "Overlap", None))),
    )
    colors = ("#25496b", "#c55c28", "#55958a")
    for name, ylabel, series in specs:
        fig, ax = plt.subplots(figsize=(max(7, len(x) * 1.2), 4.5), layout="constrained")
        width = 0.72 / len(series)
        for i, (key, label, intervals) in enumerate(series):
            centers = [n + width * (i - (len(series) - 1) / 2) for n in x]
            y = [r[key] for r in summary]
            errors = None
            if intervals:
                errors = [[v - r[f"{intervals}_min"] for v, r in zip(y, summary)],
                          [r[f"{intervals}_max"] - v for v, r in zip(y, summary)]]
            ax.bar(centers, y, width, label=label, yerr=errors, capsize=3, color=colors[i])
        if name in ("speedup", "imbalance"):
            ax.axhline(1, color="#444444", linewidth=1, linestyle="--")
        ax.set(ylabel=ylabel, xticks=x, xticklabels=labels)
        ax.set_title("FireFront-HPC · 8192 × 8192, 400 steps, 16 ignitions")
        ax.grid(axis="y", alpha=0.25)
        ax.set_axisbelow(True)
        ax.spines[["top", "right"]].set_visible(False)
        ax.legend(frameon=False)
        fig.savefig(out / f"e7_{name}.png", dpi=300)
        fig.savefig(out / f"e7_{name}.pdf")
        plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", type=Path)
    parser.add_argument("--tables", type=Path, default=Path("results/tables"))
    parser.add_argument("--figures", type=Path, default=Path("results/figures"))
    parser.add_argument("--csv-only", action="store_true")
    args = parser.parse_args()
    try:
        pairs = list(read_pairs(sorted(args.logs.glob("e7_overlap_*.out"))))
        if not pairs:
            parser.exit(1, "No completed benchmark pairs. No files written.\n")
        summary = list(summarize(pairs))
    except (ValueError, KeyError) as error:
        parser.exit(1, f"Invalid E7 input: {error}\n")
    args.tables.mkdir(parents=True, exist_ok=True)
    write_csv(args.tables / "e7_runs.csv", [row for pair in pairs for row in pair])
    write_csv(args.tables / "e7_summary.csv", summary)
    if not args.csv_only:
        args.figures.mkdir(parents=True, exist_ok=True)
        plot(summary, args.figures)


if __name__ == "__main__":
    main()
