#!/usr/bin/env bash
# Copy the addon into WoW Forever's AddOns folder, replacing what's there.
# Usage: Tools/deploy.sh   (override the target with WOW_FOREVER_ADDONS=...)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/XpieUI-Forever"
ADDONS="${WOW_FOREVER_ADDONS:-/Applications/World of Warcraft/_forever_/Interface/AddOns}"
DEST="$ADDONS/XpieUI-Forever"

[ -d "$SRC" ] || { echo "No addon folder at $SRC" >&2; exit 1; }
[ -d "$ADDONS" ] || { echo "AddOns folder not found: $ADDONS" >&2; exit 1; }

rsync -a --delete --exclude '.DS_Store' "$SRC/" "$DEST/"

VERSION="$(grep -m1 '^## Version:' "$SRC/XpieUI-Forever.toc" | sed 's/^## Version:[[:space:]]*//')"
echo "Deployed XpieUI-Forever $VERSION to $DEST"
echo "In game: /reload (or restart WoW if files were added)."
