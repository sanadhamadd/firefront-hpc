"""Collect the RESULT lines of all run logs into one CSV.

Usage:
    python tools/parse_logs.py results/raw > results/tables/all.csv

Every *.out file in the directory is read. Each line that starts with
"RESULT" becomes one row: its key=value pairs, plus the file name and the
Slurm job id taken from the file name (omp_123456.out -> 123456).

Keys that only some runs have (for example fields the MPI version adds later)
get their own column; runs without them leave that column empty.
"""
import argparse
import csv
import re
import sys
from pathlib import Path


def job_id_from_name(name):
    """Digits just before .out, as in the Slurm templates (<name>_%j.out)."""
    m = re.search(r"(\d+)\.out$", name)
    return m.group(1) if m else ""


def parse_result_line(line):
    """'RESULT a=1 b=x' -> {'a': '1', 'b': 'x'}. Tokens without '=' are ignored."""
    fields = {}
    for token in line.split()[1:]:
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


def read_logs(directory):
    rows = []
    files = sorted(Path(directory).glob("*.out"))
    for path in files:
        with open(path, errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line.startswith("RESULT "):
                    continue
                row = {"file": path.name, "job_id": job_id_from_name(path.name)}
                row.update(parse_result_line(line))
                rows.append(row)
    return files, rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("directory", help="folder with the .out logs, e.g. results/raw")
    args = ap.parse_args()

    if not Path(args.directory).is_dir():
        sys.exit(f"not a directory: {args.directory}")

    files, rows = read_logs(args.directory)

    # columns in the order they first appear, so new fields end up on the right
    columns = []
    for row in rows:
        for key in row:
            if key not in columns:
                columns.append(key)

    w = csv.DictWriter(sys.stdout, fieldnames=columns, restval="", lineterminator="\n")
    w.writeheader()
    w.writerows(rows)
    print(f"parsed {len(rows)} RESULT lines from {len(files)} files", file=sys.stderr)


if __name__ == "__main__":
    main()
