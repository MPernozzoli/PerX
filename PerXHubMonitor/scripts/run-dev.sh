#!/bin/bash
#
# Run PerX Hub Monitor in development mode
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_DIR="$(dirname "$SCRIPT_DIR")"

cd "$MONITOR_DIR"

echo "Building and running PerX Hub Monitor..."
swift run

