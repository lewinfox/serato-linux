#!/usr/bin/env bash
# Run Serato DJ Pro in the container. Arguments go to files/serato-wine:
#   ./run.sh --install FILE   set up the prefix and run the Serato installer (.exe or .zip)
#   ./run.sh --check          report problems, change nothing
#   ./run.sh                  launch
#   ./run.sh bash             a shell inside the container
#   ./run.sh --tmp [...]      any of the above, on a throwaway copy in /tmp/serato-tmp
# Plug the controller in BEFORE starting: Docker only sees devices present at start.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

source ./paths.sh

# --tmp: a throwaway instance in /tmp/serato-tmp. The first run copies the real prefix
# (so Serato is installed) minus Serato's settings, and uses an empty Music folder.
# Later --tmp runs reuse it; rm -rf /tmp/serato-tmp to start fresh.
if [[ "${1:-}" == --tmp ]]; then
  shift
  TMP=/tmp/serato-tmp
  if [[ ! -d $TMP/data/prefix ]]; then
    echo "run.sh: copying Wine prefix to $TMP (a few GB)..." >&2
    mkdir -p "$TMP/data"
    cp -a "$PREFIX" "$TMP/data/prefix.partial"
    rm -rf "$TMP/data/prefix.partial/drive_c/users/dj/AppData/Local/Serato"
    mv "$TMP/data/prefix.partial" "$TMP/data/prefix"
  fi
  PREFIX="$TMP/data/prefix" CACHE="$TMP/cache" MUSIC="$TMP/Music"
  mkdir -p "$MUSIC"
fi
mkdir -p "$PREFIX" "$CACHE"

args=(
  --rm --name serato
  --network host                               # sign-in / streaming logins may redirect to localhost
  --ipc=host                                   # X11 shared memory
  --cap-add SYS_NICE --ulimit rtprio=95 --ulimit memlock=-1
  --security-opt apparmor=unconfined           # lets Wine reach UDisks on the system D-Bus (USB drives)
  -e LC_ALL=C.UTF-8                            # without it Wine garbles non-ASCII filenames (ō, é) and can't open them
  # screen (XWayland)
  -e DISPLAY="${DISPLAY:-:0}" -v /tmp/.X11-unix:/tmp/.X11-unix:ro
  # sound: raw ALSA for the controller, PipeWire for the laptop speakers
  -v /dev/snd:/dev/snd --device-cgroup-rule='c 116:* rmw'   # live, so a controller plugged in later appears
  # USB + device enumeration (wineusb, winebus)
  -v /dev/bus/usb:/dev/bus/usb --device-cgroup-rule='c 189:* rmw'
  # read-only raw access to USB disks (Wine detects FAT32 from the boot sector)
  --device-cgroup-rule='b 8:* r'
  -v /run/udev:/run/udev:ro
  # data
  -v "$PREFIX:/home/dj/prefix"
  -v "$CACHE:/home/dj/.cache"
  -v "$MUSIC:/home/dj/Music"
)

# --install FILE: mount the installer's folder read-only and pass its container path.
if [[ "${1:-}" == --install ]]; then
  [[ -f "${2:-}" ]] || { echo "usage: ./run.sh --install /path/to/SeratoDJPro.exe" >&2; exit 2; }
  inst="$(readlink -f "$2")"
  args+=(-v "$(dirname "$inst"):/installer:ro")
  set -- --install "/installer/$(basename "$inst")"
fi

# X auth cookie (GNOME/mutter keeps XWayland's in XDG_RUNTIME_DIR)
if [[ -n "${XAUTHORITY:-}" && -f "$XAUTHORITY" ]]; then
  args+=(-v "$XAUTHORITY:/tmp/xauth:ro" -e XAUTHORITY=/tmp/xauth)
fi
[[ -S "$RUNTIME/pipewire-0" ]]   && args+=(-v "$RUNTIME/pipewire-0:/run/pipewire-0" -e PIPEWIRE_REMOTE=/run/pipewire-0)
[[ -S "$RUNTIME/pulse/native" ]] && args+=(-v "$RUNTIME/pulse/native:/run/pulse-native" -e PULSE_SERVER=unix:/run/pulse-native)
[[ -S /run/dbus/system_bus_socket ]] && args+=(-v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket)
[[ -d /media/$USER ]] && args+=(-v "/media/$USER:/media/$USER:rslave")   # USB sticks

# GPU, in the host's video/render groups
[[ -d /dev/dri ]] && args+=(--device /dev/dri)
for g in video render; do gid="$(getent group $g | cut -d: -f3)" && args+=(--group-add "$gid"); done

# Fast Wine sync (sudo modprobe ntsync)
[[ -e /dev/ntsync ]] && args+=(--device /dev/ntsync)

# hidraw nodes are created by files/devmirror (DJ-controller vendors only); allow their major here
HIDRAW_MAJOR="$(awk '$2=="hidraw"{print $1}' /proc/devices)"
[[ -n $HIDRAW_MAJOR ]] && args+=(--device-cgroup-rule="c $HIDRAW_MAJOR:* rw")

[[ -n "${WINEDEBUG:-}" ]] && args+=(-e WINEDEBUG="$WINEDEBUG")
if [[ -t 0 ]]; then args+=(-it); elif [[ "${1:-}" == bash ]]; then args+=(-i); fi   # -i: allow piping commands into ./run.sh bash

# Browser bridge: the container's xdg-open writes URLs to this FIFO, and we open
# http(s) ones in the host browser (sign-in). Nothing else is accepted, so the
# container can't make the host open files or run handlers.
mkdir -p -m 700 "$RUNTIME/serato-wine"
BRIDGE="$RUNTIME/serato-wine/open-url.fifo"
rm -f "$BRIDGE" && mkfifo -m 600 "$BRIDGE"
args+=(-v "$BRIDGE:/run/open-url")
(
  # Outer loop reopens the FIFO after each writer closes it (EOF).
  while true; do
    while read -r url; do
      case "$url" in
        http://*|https://*) xdg-open "$url" >/dev/null 2>&1 & ;;
        *) echo "run.sh: ignored non-web URL from container: $url" >&2 ;;
      esac
    done < "$BRIDGE"
  done
) &
LISTENER=$!

# Start files/devmirror as root once the container is up (see that file for why).
(
  for _ in $(seq 60); do docker exec serato true 2>/dev/null && break; sleep 1; done
  exec docker exec -u root -e HID_VENDORS="${HID_VENDORS:-}" serato /usr/local/bin/devmirror
) >/dev/null 2>&1 &
DEVMIRROR=$!
trap 'kill $LISTENER $DEVMIRROR 2>/dev/null; rm -f "$BRIDGE"' EXIT

if [[ "${1:-}" == bash ]]; then
  docker run "${args[@]}" serato-wine bash
else
  # Wait (up to 10 s) for devmirror's first pass, so Wine's startup drive scan finds
  # sticks that are already plugged in.
  docker run "${args[@]}" serato-wine sh -c '
    for i in $(seq 50); do [ -e /dev/.devmirror-ready ] && break; sleep 0.2; done
    exec serato-wine "$@"' \
    serato-wine "$@"
fi
