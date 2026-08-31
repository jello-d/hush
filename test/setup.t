#!/bin/sh
# setup.t - setup.sh install -> assert the shell links + the mako config symlink
# + the seeded placement.active (and NOT the tray launcher, a `service`-only
# thing) -> check -> uninstall -> assert gone. A scratch PREFIX; nothing outside
# it is touched. `service` is not exercised: its venv build + systemctl reach
# the real session/network.
. "$(dirname "$0")/lib.sh"
harness_init setup

BIN=$T/bin; SHR=$T/share; CFG=$T/config
run() {
  env PREFIX="$T" XDG_BIN_HOME="$BIN" XDG_DATA_HOME="$SHR" \
    XDG_CONFIG_HOME="$CFG" NO_COLOR=1 sh "$HERE/setup.sh" "$@"
}

# install: shell tools + man + mako config linked; placement.active seeded; the
# tray launcher is NOT created (that is `service`).
run install >/dev/null 2>&1 || fail "install errored"
[ "$(readlink "$BIN/mako-placement")" = "$HERE/bin/mako-placement" ] \
  || fail "mako-placement not linked"
[ "$(readlink "$BIN/dnd-comms-toggle")" = "$HERE/bin/dnd-comms-toggle" ] \
  || fail "dnd-comms-toggle not linked"
[ "$(readlink "$CFG/mako/config")" = "$HERE/share/mako/config" ] \
  || fail "mako config not linked"
[ -e "$CFG/mako/placement.active" ] || fail "placement.active not seeded"
[ -e "$SHR/man/man1/hush.1" ] || fail "man page not linked"
[ -e "$BIN/comms-indicator" ] && fail "install made the tray launcher (service)"

# check: green on a canonical install (deps may WARN in a sandbox, not FAIL)
run check >/dev/null 2>&1 || fail "check drifted on a canonical install"

# uninstall: the links removed (no systemctl -- no unit was installed)
run uninstall >/dev/null 2>&1 || fail "uninstall errored"
[ -e "$BIN/mako-placement" ] && fail "mako-placement link not removed"
[ -e "$CFG/mako/config" ] && fail "mako config link not removed"

pass "install + check + uninstall"
