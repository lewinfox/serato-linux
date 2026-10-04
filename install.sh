#!/usr/bin/env bash
# Interactive installer: build the image, set up the host, install Serato DJ Pro,
# the sign-in link handler, and a desktop launcher. Asks before each step. Run via `make install`.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
ROOT="$PWD"
IMAGE=serato-wine
source ./paths.sh
SERATO="$PREFIX/drive_c/Program Files/Serato"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask()  { local r; read -r -p "$1 [Y/n] " r; [[ -z $r || $r =~ ^[Yy] ]]; }

# Installed exe, Pro before Lite (as files/serato-wine picks it). Empty if neither.
serato_exe() {
  local e
  for e in Pro Lite; do
    [[ -f "$SERATO/Serato DJ $e/Serato DJ $e.exe" ]] && { echo "$SERATO/Serato DJ $e/Serato DJ $e.exe"; return; }
  done
}

# 1. Image -------------------------------------------------------------------
bold "1/5  Build the Docker image"
if docker image inspect $IMAGE >/dev/null 2>&1; then
  echo "An image '$IMAGE' already exists. Rebuilding is quick unless the Dockerfile's early steps changed."
else
  echo "First build compiles a patched Wine DLL: about 10-15 minutes."
fi
if ask "Build the image now?"; then
  make container
fi

# 2. Host setup --------------------------------------------------------------
bold "2/5  Host setup (needs sudo)"
echo "Loads ntsync and adds a udev rule for Pioneer/AlphaTheta HID devices."
echo "Writes two files under /etc; see host-setup.sh."
if ask "Run host-setup.sh with sudo now?"; then
  sudo "$ROOT/host-setup.sh"
fi

# 3. Serato itself -----------------------------------------------------------
bold "3/5  Install Serato DJ (Pro or Lite)"
if exe="$(serato_exe)" && [[ -n $exe ]]; then
  echo "Already installed: $(basename "$exe"). (Re-run './run.sh --install FILE' with a newer installer to update.)"
else
  echo "Download the Windows installer from https://serato.com/dj/pro/downloads (or /dj/lite/downloads)"
  echo "(needs a free Serato account), then give its path here."
  guess="$(ls -t "$HOME"/Downloads/[Ss]erato*DJ*.{exe,zip} 2>/dev/null | head -1 || true)"
  read -r -e -p "Installer [${guess:-none found}]: " inst
  inst="${inst:-$guess}"
  if [[ -f $inst ]]; then
    "$ROOT/run.sh" --install "$inst"
  else
    echo "No installer; skipping. Re-run 'make install' once it's downloaded."
  fi
fi

# 4. Link handler ------------------------------------------------------------
bold "4/5  Sign-in link handler (seratodjlite:// and seratodjpro://)"
echo "Lets the browser hand sign-in redirects (Serato account, SoundCloud) back to Serato in the container."
if ask "Register the link handler now?"; then
  "$ROOT/link-handlers.sh"
fi

# 5. Desktop launcher --------------------------------------------------------
bold "5/5  Desktop launcher"
echo "Adds 'Serato DJ' to your app menu, with the icon taken from the Serato exe."
if ask "Install the desktop launcher?"; then
  exe="$(serato_exe)"
  if [[ -z $exe ]]; then
    echo "Serato isn't installed yet, so there's no icon to extract; skipping. Re-run 'make install' after step 3."
  else
    # Extract every size from the exe into a scratch dir, then install them
    # into the per-user icon theme (XDG standard location).
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    docker run --rm -v "$exe:/s.exe:ro" -v "$tmp:/out" $IMAGE \
      bash -c 'cd /out && wrestool -x -t 14 /s.exe -o s.ico && icotool -x s.ico'
    for png in "$tmp"/s_*x32.png; do
      s="$(basename "$png" | sed -E 's/s_[0-9]+_([0-9]+)x.*/\1/')"
      install -Dm644 "$png" "$ICONS/${s}x${s}/apps/serato-dj-pro.png"
      echo "  $ICONS/${s}x${s}/apps/serato-dj-pro.png"
    done
    big="$(ls "$ICONS"/*/apps/serato-dj-pro.png | sort -V | tail -1)"   # largest size
    touch "$ICONS"   # newer mtime makes GTK/GNOME rescan the theme dir
    install -Dm644 /dev/stdin "$APPS/serato-dj-pro.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Serato DJ
Comment=$(basename "$exe" .exe) in Docker (Wine)
Exec=$ROOT/run.sh
Icon=$big
Terminal=false
Categories=AudioVideo;Audio;Music;
StartupWMClass=$(basename "$exe" | tr A-Z a-z)
EOF
    gtk-update-icon-cache -q "$ICONS" 2>/dev/null || true
    update-desktop-database -q "$APPS" 2>/dev/null || true
    echo "Installed $APPS/serato-dj-pro.desktop"
  fi
fi

# Done -----------------------------------------------------------------------
bold "Next"
cat <<EOF
  Launch:        Serato DJ from the app menu, or $ROOT/run.sh
  Health check:  $ROOT/run.sh --check
  Controller:    plug it in before launching
  Music:         $MUSIC appears in Serato as C:\\users\\dj\\Music
  Library:       $MUSIC/_Serato_  (back this up)
  Wine prefix:   $PREFIX
EOF
