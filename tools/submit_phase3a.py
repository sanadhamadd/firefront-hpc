"""Plan E3/E4/E6 or submit a checked subset from the cluster login node."""
import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

from phase3a_results import LAYOUT, read_runs

STEPS = 400
LAUNCHERS = (
    "srun --cpu-bind=cores", "srun --mpi=pmi2 --cpu-bind=cores",
    "srun --mpi=pmix --cpu-bind=cores", "mpirun --bind-to core",
)


@dataclass(frozen=True)
class Case:
    experiment: str
    nx: int
    ny: int
    nodes: int
    ranks: int
    threads: int

    @property
    def hosts(self):
        return "haskell" if self.nodes == 1 else "haskell,julia"

    def layout(self):
        return self.nx, self.ny, self.nodes, self.ranks, self.threads

    def job_key(self, rep):
        return "-".join(map(str, ("phase3a", self.experiment, *self.layout(), rep)))


CASES = {
    "e3": [Case("e3", 8192, 8192, nodes, ranks, 32 // ranks)
           for nodes in (1, 2) for ranks in (8, 16, 32)],
    "e4": [Case("e4", nx, ny, nodes, ranks, threads) for nx, ny, nodes, ranks, threads in (
        (1024, 1024, 1, 1, 1), (2048, 2048, 1, 1, 4),
        (4096, 4096, 1, 4, 4), (8192, 4096, 2, 8, 4),
    )],
    "e6": [Case("e6", size, size, 1, 4, 8) for size in (2048, 4096, 8192)],
}


def matches_plan_parameters(row):
    return (row["steps"] == STEPS and row.get("decomp") == "blocks"
            and row.get("overlap") == "0" and row.get("humidity") == "0.2"
            and row.get("places") == "cores")


def planned_experiment(row):
    if matches_plan_parameters(row):
        layout = tuple(row[field] for field in LAYOUT)
        for experiment, cases in CASES.items():
            if any(case.layout() == layout for case in cases):
                return experiment
    return ""


def run(*command):
    return subprocess.check_output(command, text=True).strip()


def sbatch(case, rep):
    return [
        "sbatch", "--partition=cpu", f"--nodes={case.nodes}", f"--nodelist={case.hosts}",
        f"--ntasks={case.ranks}", f"--ntasks-per-node={case.ranks // case.nodes}",
        f"--cpus-per-task={case.threads}", "--hint=nomultithread", "--mem=4G",
        f"--comment={case.job_key(rep)}",
        f"--export=ALL,EXPERIMENT={case.experiment},NX={case.nx},NY={case.ny},"
        f"STEPS={STEPS},DECOMP=blocks,OVERLAP=0,REP={rep}",
        "slurm/hybrid.sbatch",
    ]


def confirmed_launcher(path, nodes, launcher):
    if path is None:
        raise ValueError(f"provide --probe-{nodes} with the successful launcher probe log")
    lines = path.read_text().splitlines()
    pattern = rf"works:\s+{re.escape(launcher)}\s+\(\d+ ranks on {nodes} node\(s\), checksum "
    if not any(re.match(pattern, line) for line in lines):
        raise ValueError(f"{path} does not verify {launcher} on {nodes} node(s)")
    if nodes == 2 and "MPI transport: pml=ob1 btl=self,vader,tcp" not in lines:
        raise ValueError(f"{path} does not verify the two-node TCP transport")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("experiment", choices=sorted(CASES))
    parser.add_argument("--nodes", type=int, choices=(1, 2))
    parser.add_argument("--reps", type=int, nargs="+", default=[1, 2, 3], choices=(1, 2, 3))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--preflight", action="store_true",
                      help="validate candidate allocations with Slurm without submitting")
    mode.add_argument("--submit", action="store_true")
    parser.add_argument("--limit", type=int, default=1, choices=range(1, 9), metavar="1..8")
    for nodes in (1, 2):
        parser.add_argument(f"--probe-{nodes}", type=Path)
        parser.add_argument(f"--launch-{nodes}", choices=LAUNCHERS, default=LAUNCHERS[0])
    args = parser.parse_args()
    journal = Path("results/raw/.phase3a-submissions")
    completed = {}
    for row in read_runs("results/raw", include_legacy=True):
        if matches_plan_parameters(row):
            layout = tuple(row[field] for field in LAYOUT)
            completed.setdefault((layout, row["rep"]), []).append(row["job"])

    candidates = []
    for case in CASES[args.experiment]:
        if args.nodes is not None and case.nodes != args.nodes:
            continue
        for rep in sorted(set(args.reps)):
            key = case.job_key(rep)
            record = journal / key
            jobs = completed.get((case.layout(), rep))
            if jobs:
                print(f"Skip {key} (matching checked log(s) {jobs})")
            elif record.exists():
                print(f"Skip {key} (submission journal: {record.read_text().strip()})")
            else:
                candidates.append((case, key, record, sbatch(case, rep)))

    if not (args.submit or args.preflight):
        for case, _, _, command in candidates:
            print(f"LAUNCH={shlex.quote(getattr(args, f'launch_{case.nodes}'))} {shlex.join(command)}")
        return
    if not candidates:
        return

    queued = run("squeue", "-h", "-u", os.environ["USER"], "-o", "%i|%j|%k").splitlines()
    for line in queued:
        job, name, comment = line.split("|", 2)
        if args.submit and name.strip() == "firefront" and not comment.strip().startswith("phase3a-"):
            raise ValueError(f"existing FireFront job {job} needs reconciliation before submitting")
    active = {line.split("|", 2)[-1].strip() for line in queued}
    # The accounting comment also catches jobs submitted from another checkout.
    history = run("sacct", "-X", "-n", "-P", "-S", "2026-01-01", "-u",
                  os.environ["USER"], "-o", "Comment%128").splitlines()
    known = active | {line.strip() for line in history}
    candidates = [entry for entry in candidates if entry[1] not in known]
    selected = candidates[:max(0, min(args.limit, 8 - len(queued)))]
    if not selected:
        print("No new jobs fit the queue or all candidates have accounting records.")
        return
    for case, _, _, command in selected:
        confirmed_launcher(getattr(args, f"probe_{case.nodes}"), case.nodes,
                           getattr(args, f"launch_{case.nodes}"))
        env = {**os.environ, "LAUNCH": getattr(args, f"launch_{case.nodes}"), "REFERENCE": ""}
        subprocess.run([command[0], "--test-only", *command[1:]], check=True, env=env)
    if args.preflight:
        return

    journal.mkdir(exist_ok=True)
    for case, key, record, command in selected:
        try:
            with record.open("x") as file:
                file.write("submission started; reconcile with Slurm before retrying\n")
                file.flush()
                os.fsync(file.fileno())
        except FileExistsError:
            print(f"Skip {key} (already claimed)")
            continue
        env = {**os.environ, "LAUNCH": getattr(args, f"launch_{case.nodes}"), "REFERENCE": ""}
        job = subprocess.check_output([command[0], "--parsable", *command[1:]],
                                      text=True, env=env).strip()
        if not re.fullmatch(r"\d+(?:;[^\s]+)?", job):
            raise ValueError(f"unexpected sbatch response for {key}: {job}")
        record.write_text(job + "\n")
        print(f"Submitted {key} as {job}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        sys.exit(str(exc))
