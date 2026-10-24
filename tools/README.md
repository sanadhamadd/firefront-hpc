# tools

| file | purpose | status |
|---|---|---|
| `prototype/fire_prototype.py` | NumPy version of the fire rules, used to check how the model behaves | works |
| `prototype/imbalance_demo.py` | counts how much work each block of a 4x4 or 16-strip split would get | works |
| `capture_env.sh` | environment snapshot for each batch of runs | works |
| `parse_logs.py` | turn the RESULT lines of the logs into one CSV | to do |
| `make_plots.py` | build all figures from that CSV | to do |
| `make_landscape.py` | prepare real terrain data | to do (optional) |

Run the prototype:

    pip install -r env/requirements.txt
    python tools/prototype/fire_prototype.py --out docs/img/prototype_fire_front.png
