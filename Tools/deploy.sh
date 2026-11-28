#!/usr/bin/env bash
# Copy the addon into WoW Forever's AddOns folder, replacing what's there.
# Usage: Tools/deploy.sh   (override the target with WOW_FOREVER_ADDONS=...)
# Works on macOS/Linux (rsync) and Windows Git Bash (robocopy).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/XpieUI-Forever"

if [ -n "${WOW_FOREVER_ADDONS:-}" ]; then
    ADDONS="$WOW_FOREVER_ADDONS"
else
    ADDONS=""
    for candidate in \
        "/d/World of Warcraft/_forever_/Interface/AddOns" \
        "/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns" \
        "/Applications/World of Warcraft/_forever_/Interface/AddOns"; do
        if [ -d "$candidate" ]; then ADDONS="$candidate"; break; fi
    done
    [ -n "$ADDONS" ] || { echo "AddOns folder not found; set WOW_FOREVER_ADDONS" >&2; exit 1; }
fi
DEST="$ADDONS/XpieUI-Forever"

[ -d "$SRC" ] || { echo "No addon folder at $SRC" >&2; exit 1; }
[ -d "$ADDONS" ] || { echo "AddOns folder not found: $ADDONS" >&2; exit 1; }

if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude '.DS_Store' "$SRC/" "$DEST/"
elif command -v robocopy >/dev/null 2>&1; then
    # /MIR mirrors (deletes extras). Exit codes below 8 mean success.
    set +e
    MSYS_NO_PATHCONV=1 robocopy "$(cygpath -w "$SRC")" "$(cygpath -w "$DEST")" \
        /MIR /XF .DS_Store /NJH /NJS /NFL /NDL /NP >/dev/null
    code=$?
    set -e
    [ "$code" -lt 8 ] || { echo "robocopy failed (exit $code)" >&2; exit 1; }
else
    echo "Neither rsync nor robocopy is available" >&2
    exit 1
fi

VERSION="$(grep -m1 '^## Version:' "$SRC/XpieUI-Forever.toc" | sed 's/^## Version:[[:space:]]*//')"
echo "Deployed XpieUI-Forever $VERSION to $DEST"
echo "In game: /reload (or restart WoW if files were added)."
