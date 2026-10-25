"""Remove other people's user and job names from Slurm job logs.

Usage:
    python tools/anonymize_logs.py results/raw

Our job scripts log "squeue -w <node>" so we can see who else was on the node.
Those lines contain other users' names and job names, which do not belong in a
public repository. This script rewrites every *.out and *.txt file in the folder
in place:
    our own account          -> self
    other users              -> user1, user2, ... (in order of first appearance)
    other users' job names   -> job1, job2, ...
Job id, partition, state, run time, CPUs and memory stay, so the logs still show
how busy the node was. Our own account is found automatically: it is the user of
the job whose id is in the log's file name (e.g. e2_omp_threads_24883.out).

The mapping is only counted on the screen, never written to a file. Running the
script again changes nothing.
"""
import argparse
import re
import sys
from pathlib import Path

# a squeue line as printed by slurm/job_helpers.sh (before the change that dropped names):
# JOBID PARTITION NAME USER ST TIME CPUS MIN_MEMORY NODELIST(REASON)
SQUEUE_LINE = re.compile(r"^(\s*)(\d[\d+_]*)(\s+)(\S+)(\s+)(\S+)(\s+)(\S+)(\s+)(.*)$")
ANON_USER = re.compile(r"^(self|user\d+)$")
ANON_JOB = re.compile(r"^job\d+$")
OUR_JOB_NAMES = {"firefront"}


def job_id_from_name(name):
    m = re.search(r"_(\d+)\.(out|txt)$", name)
    return m.group(1) if m else None


def squeue_rows(text):
    """(line index, match) for every squeue data line; header lines are skipped.

    Only tables in the old format (with NAME and USER columns) are touched; the newer
    logs print WHO = self/other instead and contain no names."""
    rows = []
    in_table = False
    for i, line in enumerate(text.splitlines()):
        if line.strip().startswith("JOBID"):
            in_table = " NAME " in line and " USER " in line
            continue
        m = SQUEUE_LINE.match(line) if in_table else None
        if m:
            rows.append((i, m))
        else:
            in_table = False
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("directory", help="folder with the logs, e.g. results/raw")
    args = ap.parse_args()

    files = sorted(p for p in Path(args.directory).iterdir()
                   if p.suffix in (".out", ".txt") and p.is_file())
    texts = {p: p.read_text(errors="replace") for p in files}

    # pass 1: find our own account and collect the other names in order of appearance
    self_users, others, jobs = set(), [], []
    for p in files:
        own_id = job_id_from_name(p.name)
        for _, m in squeue_rows(texts[p]):
            jobid, name, user = m.group(2), m.group(6), m.group(8)
            if own_id and jobid == own_id and not ANON_USER.match(user):
                self_users.add(user)
    for p in files:
        for _, m in squeue_rows(texts[p]):
            name, user = m.group(6), m.group(8)
            if user in self_users or ANON_USER.match(user):
                continue
            if user not in others:
                others.append(user)
            if name not in OUR_JOB_NAMES and not ANON_JOB.match(name) and name not in jobs:
                jobs.append(name)

    user_map = {u: "self" for u in self_users}
    user_map.update({u: f"user{k + 1}" for k, u in enumerate(others)})
    job_map = {j: f"job{k + 1}" for k, j in enumerate(jobs)}

    # pass 2: rewrite the squeue lines, then replace the user names anywhere else as whole words
    changed = 0
    for p in files:
        lines = texts[p].splitlines(keepends=True)
        for i, m in squeue_rows(texts[p]):
            name, user = m.group(6), m.group(8)
            new_user = user_map.get(user, user)
            new_name = name if user in self_users else job_map.get(name, name)
            g = list(m.groups())
            g[5], g[7] = new_name.rjust(len(name)), new_user.rjust(len(user))
            end = "\n" if lines[i].endswith("\n") else ""
            lines[i] = "".join(g) + end
        new = "".join(lines)
        for old, anon in user_map.items():
            new = re.sub(rf"\b{re.escape(old)}\b", anon, new)
        if new != texts[p]:
            p.write_text(new)
            changed += 1

    print(f"{len(files)} files read, {changed} changed; replaced {len(self_users)} own account, "
          f"{len(others)} other users and {len(jobs)} other job names (mapping not saved)",
          file=sys.stderr)


if __name__ == "__main__":
    main()
