#!/bin/bash
#
# Wrapper per WA Bridge - risolve il path di node dinamicamente
#

# Trova node nel PATH standard
NODE_PATH=""
for np in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node; do
    if [ -x "$np" ]; then
        NODE_PATH="$np"
        break
    fi
done

# Fallback: prova which
if [ -z "$NODE_PATH" ]; then
    NODE_PATH=$(which node 2>/dev/null)
fi

if [ -z "$NODE_PATH" ] || [ ! -x "$NODE_PATH" ]; then
    echo "[ERROR] node non trovato. Installa Node.js 18+ con Homebrew: brew install node"
    exit 1
fi

cd /opt/perx-hub/workers/wa-bridge

echo "[WA Bridge] Avvio con node: $NODE_PATH"
exec "$NODE_PATH" src/index.js
