#!/bin/bash
# Run from the repository root. The default is a read-only plan.
set -eu
exec python3 tools/submit_phase3a.py "$@"
