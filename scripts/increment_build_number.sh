#!/bin/bash

# Script per incrementare automaticamente il build number quando si fa Archive
# Esegue solo per build di Archive, non per build normali

set -e

# Esegue solo durante Archive
if [ "${ACTION}" != "install" ] && [ "${ACTION}" != "archive" ]; then
    exit 0
fi

PROJECT_FILE="${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "❌ Project file not found: $PROJECT_FILE"
    exit 1
fi

# Trova il build number corrente per il target principale "PerX"
# Cerca la sezione del target PerX (non PerX Lite) e estrae CURRENT_PROJECT_VERSION
# Usa un approccio più robusto: cerca il blocco di build settings del target PerX
CURRENT_BUILD=$(awk '
    /PerX.app.*=.*PBXFileReference/ { in_perx_target = 1; next }
    in_perx_target && /CURRENT_PROJECT_VERSION = / {
        match($0, /CURRENT_PROJECT_VERSION = ([0-9]+);/, arr)
        if (arr[1] != "" && arr[1] != "1") {
            print arr[1]
            exit
        }
    }
    /};/ && in_perx_target { in_perx_target = 0 }
' "$PROJECT_FILE")

# Fallback: cerca la prima occorrenza di CURRENT_PROJECT_VERSION con valore > 1
if [ -z "$CURRENT_BUILD" ]; then
    CURRENT_BUILD=$(grep "CURRENT_PROJECT_VERSION = " "$PROJECT_FILE" | grep -v "= 1;" | head -1 | sed -E 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/')
fi

if [ -z "$CURRENT_BUILD" ] || [ "$CURRENT_BUILD" = "1" ]; then
    echo "⚠️  Could not find valid build number, defaulting to 1"
    CURRENT_BUILD=1
fi

# Incrementa il build number
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "📦 Incrementing build number: $CURRENT_BUILD → $NEW_BUILD"

# Aggiorna il build number nel project.pbxproj
# Sostituisce solo le occorrenze nel target PerX (evita di toccare PerX Lite)
# Usa perl per sostituire in modo più sicuro
perl -i -pe "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g if /PerX\.app/ .. /};/ && !/PerX Lite/" "$PROJECT_FILE" 2>/dev/null || \
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PROJECT_FILE"

echo "✅ Build number updated to $NEW_BUILD"
