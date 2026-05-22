#!/bin/bash

# Script per convertire le icone SVG in PNG
# Richiede: ImageMagick (brew install imagemagick)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICONS_DIR="$SCRIPT_DIR/../icons"

cd "$ICONS_DIR"

echo "Conversione icone SVG -> PNG..."

# Converti ogni icona
for size in 16 48 128; do
  if [ -f "icon${size}.svg" ]; then
    echo "  Convertendo icon${size}.svg -> icon${size}.png"
    convert -background none "icon${size}.svg" -resize ${size}x${size} "icon${size}.png"
  fi
done

echo "Fatto! Icone PNG create in $ICONS_DIR"
ls -la *.png 2>/dev/null || echo "Nessun file PNG trovato (verifica ImageMagick)"
