#!/bin/bash

# Script per vedere i log di PerX in tempo reale

echo "🔍 Log di PerX in tempo reale"
echo "Premi Ctrl+C per uscire"
echo ""

# Mostra solo i log di PerX
log stream --predicate 'process == "PerX" OR senderImagePath CONTAINS "PerX"' --level debug

