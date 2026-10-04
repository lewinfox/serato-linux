# Where things live on the host, in the XDG folders. Sourced by the other scripts.
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/serato-wine"   # Wine prefix (Serato and its settings)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/serato-wine"       # the container's ~/.cache
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/serato-wine" # link handler log
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PREFIX="$DATA/prefix"
# The music folder from xdg-user-dirs (xdg-user-dir prints $HOME when none is set).
# Serato keeps its library, _Serato_, in here.
if [[ -z ${MUSIC:-} ]]; then
  MUSIC="$(xdg-user-dir MUSIC 2>/dev/null || true)"
  [[ -n $MUSIC && $MUSIC != "$HOME" ]] || MUSIC="$HOME/Music"
fi

# Older checkouts kept everything in ./data. Stop rather than start an empty prefix.
if [[ -d data/prefix && ! -d $PREFIX ]]; then
  echo "Serato's Wine prefix is still in $PWD/data; move it to $DATA first:" >&2
  echo "  mkdir -p '$DATA' && mv data/prefix '$PREFIX'" >&2
  exit 1
fi
