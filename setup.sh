#!/bin/sh
# setup.sh - install / uninstall / check / test the hush notifications suite:
# a trinary filter (all / work / none) over mako, a per-display placement/sizing
# resolver, and an SNI tray icon for the filter state. The SINGLE entry point a
# consumer or provisioning layer uses.
#
#   ./setup.sh install     shell tools (+ man) + the default mako config
#   ./setup.sh service     build the tray-icon venv + enable its --user daemon
#   ./setup.sh all         install + service
#   ./setup.sh uninstall   remove the links + the daemon (mako config left)
#   ./setup.sh check       tools + deps present; [OK]/[FAIL] markers; drift rc
#   ./setup.sh test        run the in-repo test suite (test/run)
#   ./setup.sh version     the packaged version
#
# POSIX sh, non-privileged. `install` is the shell mechanism + config (what a
# provisioner delegates to); the tray icon is a Python/dbus daemon, so it is a
# separate `service` verb (builds a venv, no venv-run dependency). PREFIX + the
# XDG_* vars override the destinations for a sandboxed test.
set -eu

PKG=hush
VERSION=0.1.0
_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

PREFIX=${PREFIX:-$HOME/.local}
_bin=${XDG_BIN_HOME:-$PREFIX/bin}
_shr=${XDG_DATA_HOME:-$PREFIX/share}
_man=$_shr/man
_cfg=${XDG_CONFIG_HOME:-$HOME/.config}
_usr=$_cfg/systemd/user
VENV=${HUSH_VENV:-$HOME/.venvs/hush}
DEPS="mako makoctl"   # the filter drives mako; the tray needs a tray host
RC=0

# marker contract: plain [OK]/[FAIL]/[WARN] an integrator styles in its palette;
# self-coloured at a terminal, plain when piped or under NO_COLOR.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _G=$(printf '\033[32m'); _R=$(printf '\033[31m')
  _Y=$(printf '\033[33m'); _O=$(printf '\033[0m')
else _G=; _R=; _Y=; _O=; fi
ok()   { printf '  %s[OK]%s   %s\n' "$_G" "$_O" "$1"; }
bad()  { printf '  %s[FAIL]%s %s\n' "$_R" "$_O" "$1"; RC=1; }
warn() { printf '  %s[WARN]%s %s\n' "$_Y" "$_O" "$1"; }

_ln()   { mkdir -p "$(dirname "$2")"; ln -sfn "$1" "$2"; }
_rmln() { [ "$(readlink "$2" 2>/dev/null)" = "$1" ] && rm -f "$2" || :; }
_man_pages() { for _m in "$_root"/man/man*/*.[0-9]; do
  [ -e "$_m" ] && printf '%s\n' "$_m"; done; }

do_install() {
  mkdir -p "$_bin" "$_cfg/mako"
  for _t in "$_root"/bin/*; do _ln "$_t" "$_bin/$(basename "$_t")"; done
  _man_pages | while IFS= read -r _m; do
    _ln "$_m" "$_man/$(basename "$(dirname "$_m")")/$(basename "$_m")"; done
  # The mako config is hush's (appearance + the dnd modes); symlink it so repo
  # edits propagate. It include's placement.active LAST, so seed that (a real
  # file mako-placement rewrites) or mako won't start (missing include).
  _ln "$_root/share/mako/config" "$_cfg/mako/config"
  [ -e "$_cfg/mako/placement.active" ] \
    || cp "$_root/share/mako/default.conf" "$_cfg/mako/placement.active"
  echo "$PKG: linked the tools (+ man) + the mako config into $PREFIX / $_cfg"
}

do_service() {
  command -v python3 >/dev/null 2>&1 || {
    echo "$PKG: python3 absent; no tray-icon venv" >&2; return 1; }
  [ -d "$VENV" ] || python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q -r "$_root/libexec/comms-indicator.reqs"
  # A launcher: exec the venv python on the packaged daemon (replaces venv-run,
  # so the tray icon is self-contained). Absolute paths; re-run after a move.
  mkdir -p "$_bin"
  cat > "$_bin/comms-indicator" <<EOF
#!/bin/sh
exec "$VENV/bin/python" "$_root/libexec/comms-indicator" "\$@"
EOF
  chmod +x "$_bin/comms-indicator"
  mkdir -p "$_usr"
  cp "$_root/systemd/comms-indicator.service" "$_usr/comms-indicator.service"
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable comms-indicator.service 2>/dev/null || true
  systemctl --user restart comms-indicator.service 2>/dev/null || true
  echo "$PKG: comms-indicator venv + --user daemon installed + enabled"
}

do_uninstall() {
  for _t in "$_root"/bin/*; do _rmln "$_t" "$_bin/$(basename "$_t")"; done
  _man_pages | while IFS= read -r _m; do
    _rmln "$_m" "$_man/$(basename "$(dirname "$_m")")/$(basename "$_m")"; done
  _rmln "$_root/share/mako/config" "$_cfg/mako/config"
  # Only touch systemctl if the unit was actually installed -- so a sandboxed
  # uninstall (a test) never reaches the real --user manager.
  if [ -e "$_usr/comms-indicator.service" ]; then
    systemctl --user disable --now comms-indicator.service 2>/dev/null || true
    rm -f "$_usr/comms-indicator.service"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  rm -f "$_bin/comms-indicator"
  echo "$PKG: removed the links + the daemon (venv + placement.active left)"
}

do_check() {
  echo "== $PKG (notifications: filter + placement + tray) =="
  for _t in "$_root"/bin/*; do _n=$(basename "$_t")
    [ "$(readlink "$_bin/$_n" 2>/dev/null)" = "$_t" ] \
      && ok "bin/$_n linked" || bad "bin/$_n not linked"; done
  _mc=$_root/share/mako/config
  [ "$(readlink "$_cfg/mako/config" 2>/dev/null)" = "$_mc" ] \
    && ok "mako config linked" || bad "mako config not linked"
  for _d in $DEPS; do
    command -v "$_d" >/dev/null 2>&1 && ok "dep $_d present" \
      || warn "dep $_d absent (the filter/tray need it)"; done
  # The tray daemon is opt-in (`service`); audit it only once installed.
  if [ -e "$_bin/comms-indicator" ]; then
    [ -x "$VENV/bin/python" ] && ok "tray venv present" \
      || bad "tray launcher present but venv missing (setup.sh service)"
    systemctl --user is-enabled --quiet comms-indicator.service 2>/dev/null \
      && ok "comms-indicator.service enabled" \
      || bad "comms-indicator.service not enabled (setup.sh service)"
  else
    warn "tray icon not installed (run setup.sh service for it)"
  fi
}

_U="usage: setup.sh [install|service|all|uninstall|check|test|version]"
case "${1:-install}" in
  install)   do_install ;;
  service)   do_service ;;
  all)       do_install; do_service ;;
  uninstall) do_uninstall ;;
  check)     do_check; exit "$RC" ;;
  test)      exec sh "$_root/test/run" ;;
  version)   echo "$PKG $VERSION" ;;
  -h|--help|help) echo "$_U" ;;
  *) echo "setup.sh: unknown command '${1:-}'" >&2; echo "$_U" >&2; exit 2 ;;
esac
