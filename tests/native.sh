#!/bin/bash
# Runs the native-bar test against the installed Omarchy bar, in a throwaway
# nested Hyprland. The nested compositor sits hidden on a special workspace,
# keeps its own runtime directory, and draws to a headless 1920x1080 output, so
# the test bar never maps on the desktop or takes its input.
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
: "${XDG_RUNTIME_DIR:?native.sh needs a desktop session}"
SESSION_DISPLAY=$XDG_RUNTIME_DIR/${WAYLAND_DISPLAY:-wayland-1}
[[ -S $SESSION_DISPLAY ]] || { echo "native.sh: no Wayland session at $SESSION_DISPLAY" >&2; exit 1; }
# A shell started outside the session has no signature; its newest instance is it.
export HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-$(command ls -t "$XDG_RUNTIME_DIR/hypr" | head -n1)}

RUN=$(mktemp -d /tmp/groups-native.XXXXXX)
PID=
cleanup() {
  if [[ -n $PID ]]; then
    kill "$PID" 2>/dev/null || true
    # Its runtime directory goes once it has stopped writing there.
    for _ in $(seq 30); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
  fi
  rm -rf -- "$RUN"
}
trap cleanup EXIT

cat >"$RUN/hyprland.lua" <<'EOF'
hl.monitor({ output = "", mode = "1920x1080@60", position = "auto", scale = 1 })
EOF

hyprctl eval "hl.exec_cmd(\"env -u HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR='$RUN' WAYLAND_DISPLAY='$SESSION_DISPLAY' Hyprland -c '$RUN/hyprland.lua'\", { workspace = \"special:groups-test silent\" })" >/dev/null

LOCK=
for _ in $(seq 50); do
  LOCK=$(find "$RUN" -name hyprland.lock | head -n1)
  [[ -n $LOCK && -S ${LOCK%/*}/.socket.sock ]] && break
  sleep 0.2
done
[[ -n $LOCK ]] || { echo "native.sh: the nested compositor did not start" >&2; exit 1; }
PID=$(sed -n 1p "$LOCK")
nested() {
  env XDG_RUNTIME_DIR="$RUN" WAYLAND_DISPLAY="$(sed -n 2p "$LOCK")" \
    HYPRLAND_INSTANCE_SIGNATURE="$(basename -- "${LOCK%/*}")" "$@"
}

# The hidden window gets no frames from the session. Draw to a headless output
# instead, and turn the window's own output off.
nested hyprctl output create headless GROUPS-TEST >/dev/null
echo 'hl.monitor({ output = "WAYLAND-1", disabled = true })' >>"$RUN/hyprland.lua"
nested hyprctl reload >/dev/null

nested env GROUPS_NATIVE_TEST=1 "$ROOT_DIR/tests/qml.test.sh"
