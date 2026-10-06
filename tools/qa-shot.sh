#!/usr/bin/env bash
# Visual QA on the real target (Windows GPU): sync, run with dev args, grab a
# screenshot, close the game, copy it into production/qa/evidence/<name>.png.
# Usage: tools/qa-shot.sh <name> [--char=x] [--scene=y] [--time=58] [--shot=8]
set -euo pipefail
NAME="$1"; shift
SRC="$(cd "$(dirname "$0")/.." && pwd)"
WIN=/mnt/c/Users/lucas/Games/MagicalSurvive
USERDIR="/mnt/c/Users/lucas/AppData/Roaming/Godot/app_userdata/Magical Survive"
# QA uses its OWN copy (game-qa) so it never touches the folder Lucas plays from
mkdir -p "$WIN/game-qa"
rsync -a --delete --exclude '.git/' --exclude '.godot/' --exclude '.claude/' --exclude 'legacy-*/' \
  --exclude 'production/' --exclude 'CCGS*' --exclude 'tests/' "$SRC/" "$WIN/game-qa/"
"$WIN/engine/Godot_v4.7.2-stable_win64_console.exe" --headless --path "$(wslpath -w "$WIN/game-qa")" --import >/dev/null 2>&1 || true
rm -f "$USERDIR/qa.png"
ARGS=("$@")
[[ " ${ARGS[*]-} " == *" --shot="* ]] || ARGS+=("--shot=8")
cd "$WIN"
timeout 90 ./engine/Godot_v4.7.2-stable_win64_console.exe --path "$(wslpath -w "$WIN/game-qa")" -- "${ARGS[@]}" --shot-path=user://qa.png --quit-after-shot >/dev/null 2>&1 || true
mkdir -p "$SRC/production/qa/evidence"
if [[ -f "$USERDIR/qa.png" ]]; then
  cp "$USERDIR/qa.png" "$SRC/production/qa/evidence/$NAME.png"
  echo "evidence: production/qa/evidence/$NAME.png"
else
  echo "NO SCREENSHOT for $NAME"; tail -20 "$USERDIR/logs/godot.log" | tr -d '\r'; exit 1
fi
grep -E "SCRIPT ERROR|ERROR:" "$USERDIR/logs/godot.log" | tr -d '\r' | grep -v "ERR_CANT_OPEN" | head -5 || true
