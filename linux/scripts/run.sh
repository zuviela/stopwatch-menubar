#!/usr/bin/env bash
# Run the Linux port of stopwatch-menubar.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 -m stopwatch_linux
