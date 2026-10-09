#!/bin/sh
# setup.sh - install / uninstall / check / test the hush notifications suite:
# a trinary filter (all / work / none) over mako, a per-display placement/sizing
# resolver, and an SNI tray icon for the filter state. The SINGLE entry point a
# consumer or provisioning layer uses.
#
#   ./setup.sh install     shell tools (+ man) + the default mako config
#   ./setup.sh service     build the tray-icon venv + enable its --user daemon
#   ./setup.sh all         install + service
#   ./setup.sh uninstall   remove the payload, links + daemon (placement left)
#   ./setup.sh check       tools + deps present; [OK]/[FAIL] markers; drift rc
#   ./setup.sh test        run the in-repo test suite (test/run)
#   ./setup.sh version     the packaged version
#   ./setup.sh paths       every root hush owns, `KIND<TAB>PATH` per line
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
# THE PAYLOAD: one tree holding hush as shipped, per the fleet's
# install-placement rule (2026-10-01). It is a COPY, never a link into the
# source tree, so the install survives the clone it came from being re-cloned
# or wiped. bin/ and share/ must be siblings in it: mako-placement resolves
# its own path and reads ../share/mako/default.conf.
_pay=$_shr/$PKG
# The tray venv folds INTO the payload (no top-level ~/.venvs root). The old
# one is retired only once the new one is built, never before.
VENV=${HUSH_VENV:-$_pay/venv}
_oldvenv=$HOME/.venvs/$PKG
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
_man_dest() { echo "$_man/$(basename "$(dirname "$1")")/$(basename "$1")"; }

# _payload_stage: build the new payload beside the live one and swap it in.
# STAGED AND SWAPPED, never emptied in place, so a running tray daemon or a
# display hook calling mako-placement never meets a half-copied tree.
#
# THE VENV IS CARRIED ACROSS, because it is the one thing in the payload that
# is BUILT rather than shipped: `install` (the shipped files) and `service`
# (the venv) are separate verbs, often run by separate steps, so a swap that
# dropped the venv would leave the tray launcher pointing at nothing until the
# next `service`. It is moved, not copied: same path afterwards, so the
# interpreter path baked into it stays true.
_payload_stage() {
  _ps_new=$_pay.new
  _ps_old=$_pay.old
  # Checked BEFORE anything is removed (the standing rm rule): an empty or
  # relative value must never reach `rm -rf`.
  case $_pay in
  /*/*/"$PKG") ;;
  *) bad "refusing to stage a payload at '$_pay'"; return 1 ;;
  esac
  rm -rf -- "$_ps_new" "$_ps_old"
  mkdir -p "$_ps_new" || { bad "could not create $_ps_new"; return 1; }
  for _d in bin libexec share man; do
    cp -R "$_root/$_d" "$_ps_new/" || { bad "could not copy $_d"; return 1; }
  done
  # DROP BUILD DETRITUS. The repo gitignores __pycache__, so a clean clone has
  # none, but the venv python RUNS the indicator out of the clone and writes it
  # there, so a copy would ship it. A payload is what the repo ships, not what
  # running it produced; stale bytecode for a module since renamed is the kind
  # of thing that only ever confuses a later diagnosis.
  find "$_ps_new" -name __pycache__ -type d -prune \
    -exec rm -rf -- {} + 2>/dev/null || :
  if [ -d "$_pay/venv" ] && [ ! -L "$_pay/venv" ]; then
    mv -- "$_pay/venv" "$_ps_new/venv" || { bad "could not carry the venv"
      return 1; }
  fi
  if [ -e "$_pay" ] || [ -L "$_pay" ]; then
    mv -- "$_pay" "$_ps_old" || { bad "could not move the old payload"
      return 1; }
  fi
  mv -- "$_ps_new" "$_pay" || { bad "could not swap in the new payload"
    [ -e "$_ps_old" ] && mv -- "$_ps_old" "$_pay"
    return 1; }
  rm -rf -- "$_ps_old"
}

# _launcher: the tray command on PATH. It execs the venv python on the
# PAYLOAD's daemon, never the source tree's, so the running tray is the
# installed code. Absolute paths; rewritten by every install and service.
_launcher() {
  rm -f "$_bin/comms-indicator"     # never write THROUGH an old symlink
  cat > "$_bin/comms-indicator" <<EOF
#!/bin/sh
exec "$VENV/bin/python" "$_pay/libexec/comms-indicator" "\$@"
EOF
  chmod +x "$_bin/comms-indicator"
}

do_install() {
  mkdir -p "$_bin" "$_shr" "$_cfg/mako"
  _payload_stage || return 1
  for _t in "$_root"/bin/*; do _n=$(basename "$_t")
    _ln "$_pay/bin/$_n" "$_bin/$_n"; done
  _man_pages | while IFS= read -r _m; do
    _ln "$_pay/${_m#"$_root"/}" "$(_man_dest "$_m")"; done
  # The mako config is hush's (appearance + the dnd modes), linked to the
  # PAYLOAD's copy (installed-to-installed, which the rule allows), so an
  # install refreshes it. It include's placement.active LAST, so seed that (a
  # real file mako-placement rewrites) or mako won't start (missing include).
  _ln "$_pay/share/mako/config" "$_cfg/mako/config"
  [ -e "$_cfg/mako/placement.active" ] \
    || cp "$_pay/share/mako/default.conf" "$_cfg/mako/placement.active"
  # A tray launcher from before the payload execs the clone's daemon; rewrite
  # it now rather than leave it pointing there until the next `service`.
  if [ -e "$_bin/comms-indicator" ] && [ -x "$VENV/bin/python" ]; then
    _launcher
  fi
  _reload_mako
  echo "$PKG: installed to $_pay (+ links in $PREFIX and $_cfg/mako)"
}

# _reload_mako: a running mako keeps the config it read AT STARTUP, so an
# install that refreshes the file changes nothing about the daemon until
# somebody reloads it or logs out.
#
# IT COST A LIVE REGRESSION ON BOTH BOXES. A `[app-name="mux"]` rule here
# joins a notification's title and body onto one row, which is what mux's
# toast hook is built around. The rule was installed and both machines' mako
# had been running for days, so every banner rendered on three rows with a
# dim host line under the title. The file was right and the daemon had never
# read it.
#
# SAID, NOT SWALLOWED, and never fatal: this is a nicety on an install path,
# and a box with no mako running (headless, pre-login, a container) is the
# ordinary case rather than an error. A reload does NOT restart mako, so no
# notification is lost and the pid does not move, which is also why a
# process-start-time check cannot tell you whether it happened.
_reload_mako() {
  command -v makoctl >/dev/null 2>&1 || return 0
  pgrep -x mako >/dev/null 2>&1 || return 0
  if makoctl reload >/dev/null 2>&1; then
    echo "$PKG: reloaded the running mako so it reads this config"
  else
    echo "$PKG: could not reload mako; run 'makoctl reload' or log out,
  or its config will be whatever it read at startup" >&2
  fi
  return 0
}

# _retire_old_venv: the pre-payload `~/.venvs/hush`. A REBUILD, NOT A MOVE (a
# venv bakes absolute paths), and retired only after the new one answers, so
# a failed rebuild never leaves the box with neither.
_retire_old_venv() {
  [ -d "$_oldvenv" ] || return 0
  [ "$VENV" != "$_oldvenv" ] || return 0
  [ -x "$VENV/bin/python" ] || return 0
  case $_oldvenv in
  "$HOME/.venvs/$PKG") ;;
  *) warn "not retiring '$_oldvenv': unexpected shape"; return 0 ;;
  esac
  rm -rf -- "$_oldvenv"
  rmdir "$HOME/.venvs" 2>/dev/null || :
  echo "$PKG: retired the old venv at $_oldvenv"
}

do_service() {
  command -v python3 >/dev/null 2>&1 || {
    echo "$PKG: python3 absent; no tray-icon venv" >&2; return 1; }
  [ -f "$_pay/libexec/comms-indicator" ] || {
    echo "$PKG: no payload at $_pay; run setup.sh install first" >&2
    return 1; }
  [ -d "$VENV" ] || python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q -r "$_pay/share/comms-indicator.reqs"
  mkdir -p "$_bin"
  _launcher
  mkdir -p "$_usr"
  cp "$_root/systemd/comms-indicator.service" "$_usr/comms-indicator.service"
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable comms-indicator.service 2>/dev/null || true
  systemctl --user restart comms-indicator.service 2>/dev/null || true
  _retire_old_venv
  echo "$PKG: comms-indicator venv + --user daemon installed + enabled"
}

do_uninstall() {
  # Each link is removed whether it points at the payload or (an install from
  # before the payload) straight into the source tree.
  for _t in "$_root"/bin/*; do _n=$(basename "$_t")
    _rmln "$_pay/bin/$_n" "$_bin/$_n"; _rmln "$_t" "$_bin/$_n"; done
  _man_pages | while IFS= read -r _m; do _d=$(_man_dest "$_m")
    _rmln "$_pay/${_m#"$_root"/}" "$_d"; _rmln "$_m" "$_d"; done
  _rmln "$_pay/share/mako/config" "$_cfg/mako/config"
  _rmln "$_root/share/mako/config" "$_cfg/mako/config"
  # Only touch systemctl if the unit was actually installed, so a sandboxed
  # uninstall (a test) never reaches the real --user manager.
  if [ -e "$_usr/comms-indicator.service" ]; then
    systemctl --user disable --now comms-indicator.service 2>/dev/null || true
    rm -f "$_usr/comms-indicator.service"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  rm -f "$_bin/comms-indicator"
  if [ -d "$_pay" ] && [ ! -L "$_pay" ]; then
    case $_pay in
    /*/*/"$PKG") rm -rf -- "$_pay" ;;
    *) bad "refusing to remove a payload at '$_pay'" ;;
    esac
  fi
  echo "$PKG: removed $_pay (with its venv), its links and the daemon"
  [ ! -e "$_cfg/mako/placement.active" ] \
    || echo "$PKG: KEPT $_cfg/mako/placement.active (mako-placement's output)"
  [ ! -d "$_oldvenv" ] \
    || echo "$PKG: KEPT the pre-payload venv $_oldvenv; delete it by hand"
}

# _check_no_source_links: nothing hush installed may resolve into the source
# tree it was installed FROM (a checkout or a provisioner's clone). That is
# the place-not-link rule itself, so it is asserted, not assumed.
_check_no_source_links() {
  _hits=$(for _l in "$_bin"/* "$_man"/man*/* "$_cfg/mako/config"; do
    [ -L "$_l" ] || continue
    case $(readlink -f "$_l" 2>/dev/null) in
    "$_root"/*) printf '%s\n' "$_l" ;;
    esac
  done)
  if [ -n "$_hits" ]; then
    # shellcheck disable=SC2086 # split on purpose: one line, space-joined
    bad "links into the source tree $_root:$(printf ' %s' $_hits)"
  else
    ok "nothing links into the source tree"
  fi
  if [ -e "$_bin/comms-indicator" ] \
     && grep -qF "$_root/" "$_bin/comms-indicator"; then
    bad "tray launcher execs the source tree (setup.sh service)"
  fi
}

_check_tray() {
  # The tray daemon is opt-in (`service`); audit it only once installed.
  if [ ! -e "$_bin/comms-indicator" ]; then
    warn "tray icon not installed (run setup.sh service for it)"
    return 0
  fi
  [ -x "$VENV/bin/python" ] && ok "tray venv present ($VENV)" \
    || bad "tray launcher present but venv missing (setup.sh service)"
  systemctl --user is-enabled --quiet comms-indicator.service 2>/dev/null \
    && ok "comms-indicator.service enabled" \
    || bad "comms-indicator.service not enabled (setup.sh service)"
  if [ -d "$_oldvenv" ] && [ "$VENV" != "$_oldvenv" ]; then
    warn "retired venv survives: $_oldvenv (setup.sh service removes it)"
  fi
}

do_check() {
  echo "== $PKG (notifications: filter + placement + tray) =="
  if [ -L "$_pay" ]; then
    bad "$_pay is a SYMLINK: the install still depends on a source tree"
  elif [ -d "$_pay/bin" ] && [ -d "$_pay/libexec" ] && [ -d "$_pay/share" ]
  then ok "payload is a self-contained tree ($_pay)"
  else bad "no payload tree at $_pay (setup.sh install)"; fi
  for _t in "$_root"/bin/*; do _n=$(basename "$_t")
    [ "$(readlink "$_bin/$_n" 2>/dev/null)" = "$_pay/bin/$_n" ] \
      && ok "bin/$_n links into the payload" \
      || bad "bin/$_n does not link to $_pay/bin/$_n"; done
  [ "$(readlink "$_cfg/mako/config" 2>/dev/null)" \
    = "$_pay/share/mako/config" ] \
    && ok "mako config links into the payload" \
    || bad "mako config does not link to $_pay/share/mako/config"
  _check_no_source_links
  for _d in $DEPS; do
    command -v "$_d" >/dev/null 2>&1 && ok "dep $_d present" \
      || warn "dep $_d absent (the filter/tray need it)"; done
  _check_tray
}

# paths: the ONE declaration of every root hush owns, `KIND<TAB>PATH` per
# line. Every value is the same expression the installer uses, never
# restated, so a root cannot move here and still be reported from there.
do_paths() {
  for _t in "$_root"/bin/*; do
    printf 'bin\t%s\n' "$_bin/$(basename "$_t")"; done
  printf 'bin\t%s\n'     "$_bin/comms-indicator"
  printf 'payload\t%s\n' "$_pay"
  printf 'venv\t%s\n'    "$VENV"
  _man_pages | while IFS= read -r _m; do
    printf 'man\t%s\n' "$(_man_dest "$_m")"; done
  printf 'config\t%s\n'  "$_cfg/mako/config"
  printf 'state\t%s\n'   "$_cfg/mako/placement.active"
  printf 'unit\t%s\n'    "$_usr/comms-indicator.service"
  printf 'runtime\t%s\n' "${XDG_RUNTIME_DIR:-/tmp}/dnd-comms-state"
}

_U="usage: setup.sh [install|service|all|uninstall|check|test|version|paths]"
case "${1:-install}" in
  install)   do_install ;;
  service)   do_service ;;
  all)       do_install; do_service ;;
  uninstall) do_uninstall ;;
  check)     do_check; exit "$RC" ;;
  test)      exec sh "$_root/test/run" ;;
  version)   echo "$PKG $VERSION" ;;
  paths)     do_paths ;;
  -h|--help|help) echo "$_U" ;;
  *) echo "setup.sh: unknown command '${1:-}'" >&2; echo "$_U" >&2; exit 2 ;;
esac
