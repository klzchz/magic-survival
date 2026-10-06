#!/usr/bin/env bash
# Visual QA that never touches the Windows desktop: renders the game in a
# private virtual X server (Xvfb, CPU GL) at Lucas's resolution and saves a
# screenshot to production/qa/evidence/<name>.png.
# Usage: tools/qa-offscreen.sh <name> [--char=x] [--scene=y] [--time=58] [--shot=5]
# Needs ~/.local/xvfb (extracted .debs, see ~/.local/xvfb/start.sh).
set -euo pipefail
NAME="$1"; shift
SRC="$(cd "$(dirname "$0")/.." && pwd)"
if ! pgrep -f "Xvfb :77" >/dev/null; then
  (~/.local/xvfb/start.sh >/dev/null 2>&1 &)
  sleep 2
fi
ARGS=("$@")
[[ " ${ARGS[*]-} " == *" --shot="* ]] || ARGS+=("--shot=5")
OUT="$SRC/production/qa/evidence/$NAME.png"
mkdir -p "$(dirname "$OUT")"
DISPLAY=:77 WAYLAND_DISPLAY= timeout 150 godot4 --path "$SRC" --display-driver x11 --rendering-driver opengl3 \
  -- "${ARGS[@]}" --shot-path="$OUT" --quit-after-shot > /tmp/qa-offscreen.log 2>&1 || true
if [[ -f "$OUT" ]]; then echo "evidence: ${OUT#$SRC/}"; else echo "NO SCREENSHOT"; tail -15 /tmp/qa-offscreen.log; exit 1; fi
grep -E "SCRIPT ERROR" /tmp/qa-offscreen.log | head -5 || true
