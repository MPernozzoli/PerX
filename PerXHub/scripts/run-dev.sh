#!/bin/bash
#
# Run PerX Hub in development mode
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(dirname "$SCRIPT_DIR")"
DEV_PATH="$HOME/perx-hub-dev"

echo "=== PerX Hub Development Mode ==="
echo ""

# Create dev directories
mkdir -p "$DEV_PATH"/{data,vault,logs}
mkdir -p "$DEV_PATH/vault/sinistri"

# Set environment
export PERX_ENV=development
export PERX_HUB_PATH="$DEV_PATH"
export PERX_HUB_HOST="127.0.0.1"
export PERX_HUB_PORT="8080"

echo "Using dev path: $DEV_PATH"
echo "Server will listen on: $PERX_HUB_HOST:$PERX_HUB_PORT"
echo ""

# Build and run
cd "$HUB_DIR"
swift run PerXHub
