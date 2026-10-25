# tools

| file | purpose | status |
|---|---|---|
| `prototype/fire_prototype.py` | NumPy version of the fire rules, used to check how the model behaves | works |
| `prototype/imbalance_demo.py` | counts how much work each block of a 4x4 or 16-strip split would get | works |
| `capture_env.sh` | environment snapshot for each batch of runs | works |
| `cluster_info.sh` | what the cluster has: partitions, CPU, NUMA, modules, MPI plugins, GPUs (safe on the login node) | works; output in `env/cluster_info.txt` |
| `parse_logs.py` | turn the RESULT lines of the `.out` logs in a folder into one CSV (unknown keys get their own column) | works |
| `make_plots.py` | wall time, speed-up, efficiency and MCUPS vs physical cores (median of repetitions, min/max error bars; `places=threads` runs as a separate star) | works |
| `roofline.py` | max cell updates per second from a bandwidth in GB/s, at 10 bytes per update, counted like STREAM without write-allocate (`--bytes` to change) | works |
| `anonymize_logs.py` | replace user and job names in old job logs: own account -> self, others -> user1, job1 ...; the mapping is never saved | works |
| `make_landscape.py` | prepare real terrain data | to do (optional) |

Run the prototype:

    pip install -r env/requirements.txt
    python tools/prototype/fire_prototype.py --out docs/img/prototype_fire_front.png

Logs to figures (needs pandas and matplotlib from `env/requirements.txt`):

    python tools/parse_logs.py results/raw > results/tables/all.csv
    python tools/make_plots.py results/tables/all.csv results/figures
