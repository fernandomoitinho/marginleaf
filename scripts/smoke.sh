#!/usr/bin/env bash
# Launches the built app on a sample note, checks it stays alive, records memory use
# and takes screenshots. Meant for CI (a macOS runner has a GUI session); never fails
# the build on its own, it only produces evidence.
set -uo pipefail
cd "$(dirname "$0")/.."

OUT="build/smoke"
mkdir -p "$OUT"
APP="$PWD/build/Marginleaf.app"
SAMPLE="$PWD/scripts/smoke-sample.md"

# Comment script self-test: page JS is off, so this proves our injected script still runs.
rm -f "$OUT/selftest.json"
MARGINLEAF_SELFTEST="$PWD/$OUT/selftest.json" "$APP/Contents/MacOS/Marginleaf" "$SAMPLE" >/dev/null 2>&1 &
for _ in $(seq 1 40); do [ -s "$OUT/selftest.json" ] && break; sleep 0.5; done
echo "SMOKE: selftest -> $(cat "$OUT/selftest.json" 2>/dev/null || echo 'no output')"
cat "$OUT/selftest.json.window" 2>/dev/null | sed 's/^/SMOKE window: /'
pkill -x Marginleaf || true
sleep 1

start=$(python3 -c 'import time; print(time.time())')
open -a "$APP" "$SAMPLE"

# Wait up to 15 s for the process to exist.
for _ in $(seq 1 30); do
  pgrep -x Marginleaf >/dev/null && break
  sleep 0.5
done
if ! pgrep -x Marginleaf >/dev/null; then
  echo "SMOKE: Marginleaf did not start"
  ls -la ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i marginleaf || true
  cat ~/Library/Logs/DiagnosticReports/Marginleaf*.ips 2>/dev/null | head -80 || true
  echo "--- direct run:"
  (timeout 5 "$APP/Contents/MacOS/Marginleaf" "$SAMPLE" 2>&1 | head -30) || true
  exit 1
fi
seen=$(python3 -c 'import time; print(time.time())')
echo "SMOKE: process visible after $(python3 -c "print(round($seen - $start, 2))") s"

sleep 4
if ! pgrep -x Marginleaf >/dev/null; then
  echo "SMOKE: Marginleaf exited after launching"
  ls -la ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i marginleaf || true
  cat ~/Library/Logs/DiagnosticReports/Marginleaf*.ips 2>/dev/null | head -80 || true
  exit 1
fi
echo "SMOKE: still running after 4 s"

echo "SMOKE: memory (RSS, KB)"
ps -axo rss,comm | grep -E 'Marginleaf|WebKit' | grep -v grep || true

screencapture -x "$OUT/preview.png" || echo "SMOKE: screencapture failed"

# Cmd+E needs Accessibility permission, which a CI runner may not grant. Try anyway.
if osascript -e 'tell application "System Events" to keystroke "e" using command down' 2>/dev/null; then
  sleep 2
  screencapture -x "$OUT/source.png" || true
else
  echo "SMOKE: could not send Cmd+E (no accessibility permission)"
fi

pkill -x Marginleaf || true
exit 0
