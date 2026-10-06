#!/usr/bin/env bash
# Play on Windows with the real GPU (WSLg renders on the CPU via llvmpipe).
# Mirrors the game files to C:\Users\lucas\Games\MagicalSurvive\game and
# launches the native Godot 4.7.2 there. Usage: tools/play-windows.sh [--import-only]
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
WIN=/mnt/c/Users/lucas/Games/MagicalSurvive
EXE="$WIN/engine/Godot_v4.7.2-stable_win64.exe"
CONSOLE="$WIN/engine/Godot_v4.7.2-stable_win64_console.exe"
mkdir -p "$WIN/game"
rsync -a --delete \
  --exclude '.git/' --exclude '.godot/' --exclude '.claude/' --exclude 'legacy-*/' \
  --exclude 'production/' --exclude 'CCGS*' --exclude 'tests/' --exclude '*.deb' \
  "$SRC/" "$WIN/game/"
GAME_WIN="$(wslpath -w "$WIN/game")"
# first run (or new assets): import once, headless, so the game starts clean
"$CONSOLE" --headless --path "$GAME_WIN" --import >/dev/null 2>&1 || true
if [[ "${1:-}" == "--import-only" ]]; then exit 0; fi
cd "$WIN"
"$EXE" --path "$GAME_WIN" >/dev/null 2>&1 &
disown
echo "Magical Survive launched on Windows (GPU)."
