#!/usr/bin/env bash
# Register seratodjpro:// and seratodjlite:// links on the host, so the browser
# hands sign-in redirects to serato-link-handler.sh, which passes them into the
# running container. (The prefix side is done by serato-wine --install / --setup.)
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
ROOT="$PWD"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

rm -f "$APPS/seratodjpro-handler.desktop"   # older name
install -Dm644 /dev/stdin "$APPS/serato-link-handler.desktop" <<D
[Desktop Entry]
Type=Application
Name=Serato link handler
Exec=$ROOT/serato-link-handler.sh %u
MimeType=x-scheme-handler/seratodjpro;x-scheme-handler/seratodjlite;
NoDisplay=true
Terminal=false
D
for s in seratodjpro seratodjlite; do
  xdg-mime default serato-link-handler.desktop x-scheme-handler/$s
  echo "$s:// -> $(xdg-mime query default x-scheme-handler/$s)"
done
update-desktop-database -q "$APPS" 2>/dev/null || true
