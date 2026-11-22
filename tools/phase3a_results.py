"""Validate hybrid output and read checked Phase 3a run logs."""
import argparse
import os
from pathlib import Path
import math
import re
import sys

from parse_logs import parse_result_line

E1 = "0xb8683c550fa95bd6"
E3_JOBS = {34094, 34105, 34108, *range(34111, 34117)}
LAYOUT = ("nx", "ny", "nodes", "ranks", "threads")
HYBRID_LOG = re.compile(r"hybrid_(\d+)")
E3_LOG = re.compile(r"alejandro_e3_(?:rep(\d+)_(\d+)x(\d+)|smoke|test[23])_(\d+)")
CHECKSUM = re.compile(r"0x[0-9a-f]{16}")


def result(lines):
    records = [parse_result_line(line) for line in lines if line.startswith("RESULT ")]
    if len(records) != 1:
        raise ValueError(f"expected one RESULT, found {len(records)}")
    record = records[0]
    for field in ("t_total", "cells_per_s"):
        value = float(record[field])
        if not math.isfinite(value) or value <= 0:
            raise ValueError(f"invalid {field}: {value}")
    if not CHECKSUM.fullmatch(record["checksum"]):
        raise ValueError("invalid checksum format")
    return record


def require(record, **expected):
    for field, value in expected.items():
        if record.get(field) != str(value):
            raise ValueError(f"{field}={record.get(field)}, expected {value}")


def read_runs(directory, include_legacy=False):
    directory = Path(directory)
    paths = [*directory.glob("alejandro_e3_*.out"), *directory.glob("hybrid_*.out")]
    seen = {}
    for path in sorted(paths):
        archived = E3_LOG.fullmatch(path.stem)
        hybrid = HYBRID_LOG.fullmatch(path.stem)
        if not (archived or hybrid):
            continue
        job = int(archived[4] if archived else hybrid[1])
        lines = path.read_text(errors="replace").splitlines()
        if any(line.startswith(("CHECKSUM ", "FAILED OUTPUT:")) for line in lines):
            continue
        if "checksum ok" not in lines:
            continue
        try:
            header, = [parse_result_line("LOG " + line) for line in lines if line.startswith("rep=")]
            experiment = header.get("experiment") or ("e3" if archived or job in E3_JOBS else "")
            if not experiment and not include_legacy:
                continue
            record = result(lines)
            require(record, variant="mpi", seed=42, ignitions=16)
            refs = [line.split()[-1] for line in lines if line.startswith("serial checksum: ")]
            if (record["nx"], record["ny"], record["steps"]) == ("8192", "8192", "400"):
                reference = E1
            else:
                reference, = refs
            if refs and refs != [reference]:
                raise ValueError("inconsistent reference")
            require(record, checksum=reference)
            if archived and archived[1]:
                require(header, rep=archived[1])
                require(record, ranks=archived[2], threads=archived[3])
            record.update(job=job, experiment=experiment, rep=int(header["rep"]))
            allocations = [parse_result_line("LOG " + line) for line in lines
                           if line.startswith("decomp=")]
            if allocations:
                allocation, = allocations
                require(record, **{field: allocation[field]
                                   for field in ("decomp", "ranks", "threads", "nodes")})
                record["nodelist"] = allocation.get("nodelist", "")
            for field in ("nx", "ny", "steps", "nodes", "ranks", "threads"):
                record[field] = int(record[field])
            if min(record[field] for field in ("nodes", "ranks", "threads", "rep")) < 1:
                raise ValueError("invalid node, rank, thread or repetition count")
        except (ValueError, KeyError) as exc:
            print(f"{path}: ignoring log ({exc})", file=sys.stderr)
        else:
            identity = {field: value for field, value in record.items() if field != "nodelist"}
            if job in seen:
                if identity != seen[job]:
                    raise ValueError(f"conflicting verified records for job {job}")
                continue
            seen[job] = identity
            yield dict(record, source=path.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check"])
    parser.add_argument("nx")
    parser.add_argument("ny")
    parser.add_argument("steps")
    parser.add_argument("variant", choices=["serial", "mpi"])
    parser.add_argument("expected", nargs="*")
    args = parser.parse_args()
    try:
        record = result(sys.stdin)
        require(record, nx=args.nx, ny=args.ny, steps=args.steps, seed=42,
                ignitions=16, variant=args.variant)
        if os.environ.get("EXPECTED_COMMIT"):
            require(record, commit=os.environ["EXPECTED_COMMIT"])
        if args.variant == "serial":
            require(record, ranks=1, threads=1)
            print(record["checksum"])
        else:
            checksum, ranks, threads, nodes, decomp, overlap = args.expected
            require(record, checksum=checksum, ranks=ranks, threads=threads,
                    nodes=nodes, decomp=decomp, overlap=overlap)
    except (ValueError, KeyError) as exc:
        sys.exit(f"CHECKSUM OR RESULT ERROR: {exc}")


if __name__ == "__main__":
    main()
