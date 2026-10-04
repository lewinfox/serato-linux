#!/usr/bin/env bash
# Host handler for seratodjpro:// and seratodjlite:// links (the browser sign-in
# and SoundCloud login return to Serato through one). Passes the link into the
# running container, to the running Serato.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
url="${1:-}"
# Log each link (query string hidden: it holds a one-time login code) and what happened.
source ./paths.sh
mkdir -p "$STATE" "$RUNTIME/serato-wine"
LOG="$STATE/link-handler.log"
exec >>"$LOG" 2>&1
echo "$(date '+%F %T') ${url%%\?*}?..."
[[ $url == seratodjpro://* || $url == seratodjlite://* ]] || { echo "not a Serato link: $url" >&2; exit 1; }

if ! docker ps --format '{{.Names}}' | grep -qx serato; then
  notify-send "Serato" "Serato isn't running, so the sign-in link can't be delivered." 2>/dev/null || true
  exit 1
fi

# Firefox fires the same link twice at once, and two links passed in together
# both get lost. So deliver one at a time, and skip a repeat of the last link.
exec 9>"$RUNTIME/serato-wine/link-handler.lock"
flock 9
LAST="$RUNTIME/serato-wine/link-handler.last"
if [[ -f $LAST && "$(cat "$LAST")" == "$url" ]]; then
  echo "  duplicate; skipped"; exit 0
fi
printf '%s' "$url" > "$LAST"

# Run the exe with the link rather than `wine start`: Wine's start fails with
# "access denied" on links over ~260 characters (SoundCloud's are ~510). A second
# Serato hands the link to the running one over a pipe and exits.
# Output is dropped: Serato echoes the link, login code included.
case $url in
  seratodjlite://*) exe='C:\Program Files\Serato\Serato DJ Lite\Serato DJ Lite.exe' ;;
  *)                exe='C:\Program Files\Serato\Serato DJ Pro\Serato DJ Pro.exe' ;;
esac
rc=0; timeout 60 docker exec serato wine "$exe" "$url" >/dev/null 2>&1 || rc=$?
if (( rc == 0 )); then echo "  passed to Serato"; else
  echo "  docker exec failed: exit $rc"
fi
