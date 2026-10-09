#!/bin/sh
# setup.t - setup.sh install -> assert a self-contained payload tree, the shell
# links + the mako config linking INTO it (never into the source tree), the
# seeded placement.active (and NOT the tray launcher, a `service`-only thing)
# -> check -> reinstall carries a venv across -> uninstall -> assert gone. A
# scratch PREFIX; nothing outside it is touched. `service` is not exercised:
# its venv build + systemctl reach the real session/network.
. "$(dirname "$0")/harness_lib"
harness_init setup

BIN=$T/bin; SHR=$T/share; CFG=$T/config; PAY=$SHR/hush
run() {
  env PREFIX="$T" XDG_BIN_HOME="$BIN" XDG_DATA_HOME="$SHR" \
    XDG_CONFIG_HOME="$CFG" NO_COLOR=1 sh "$HERE/setup.sh" "$@"
}

# A pre-payload install: links straight into the source tree. install must
# replace every one of them, and check must then find none.
mkdir -p "$BIN" "$CFG/mako"
ln -s "$HERE/bin/mako-placement" "$BIN/mako-placement"
ln -s "$HERE/share/mako/config" "$CFG/mako/config"

# install: a real payload tree; tools + man + mako config link into it.
run install >/dev/null 2>&1 || fail "install errored"
[ -d "$PAY" ] && [ ! -L "$PAY" ] || fail "payload is not a real directory"
for _d in bin libexec share man; do
  [ -d "$PAY/$_d" ] || fail "payload has no $_d/"; done
[ "$(readlink "$BIN/mako-placement")" = "$PAY/bin/mako-placement" ] \
  || fail "mako-placement not linked into the payload"
[ "$(readlink "$BIN/dnd-comms-toggle")" = "$PAY/bin/dnd-comms-toggle" ] \
  || fail "dnd-comms-toggle not linked into the payload"
[ "$(readlink "$CFG/mako/config")" = "$PAY/share/mako/config" ] \
  || fail "mako config not linked into the payload"
[ "$(readlink "$SHR/man/man1/hush.1")" = "$PAY/man/man1/hush.1" ] \
  || fail "man page not linked into the payload"
[ -e "$CFG/mako/placement.active" ] || fail "placement.active not seeded"
[ -e "$BIN/comms-indicator" ] && fail "install made the tray launcher (service)"
for _l in "$BIN"/* "$SHR"/man/man1/* "$CFG/mako/config"; do
  case $(readlink -f "$_l") in
  "$HERE"/*) fail "$_l resolves into the source tree" ;;
  esac
done

# self-location: the installed mako-placement finds the PAYLOAD's default.
# hwdp and makoctl stubbed silent, so no shape is found and the live mako is
# never told to reload.
_act=$T/active.out; mkdir -p "$T/stub"
for _s in hwdp makoctl wlr-randr; do
  printf '#!/bin/sh\nexit 0\n' > "$T/stub/$_s"; chmod +x "$T/stub/$_s"; done
env MAKO_SHAPES="$T/none" MAKO_ACTIVE="$_act" PATH="$T/stub:/usr/bin:/bin" \
  "$BIN/mako-placement" >/dev/null 2>&1 || :
cmp -s "$_act" "$PAY/share/mako/default.conf" \
  || fail "installed mako-placement did not resolve the payload's default"

# check: green on a canonical install (deps may WARN in a sandbox, not FAIL)
run check >/dev/null 2>&1 || fail "check drifted on a canonical install"

# reinstall is idempotent, and carries a built venv across the payload swap.
mkdir -p "$PAY/venv/bin"; : > "$PAY/venv/bin/marker"
run install >/dev/null 2>&1 || fail "reinstall errored"
[ -e "$PAY/venv/bin/marker" ] || fail "reinstall dropped the venv"
[ -e "$PAY.new" ] || [ -e "$PAY.old" ] && fail "reinstall left a staging dir"
run check >/dev/null 2>&1 || fail "check drifted after a reinstall"

# paths: the contract verb names the payload it just installed.
run paths | grep -qx "payload	$PAY" || fail "paths does not name the payload"

# --- A RUNNING MAKO IS TOLD TO RE-READ THE CONFIG WE JUST LINKED --------
# WRITTEN BECAUSE ITS ABSENCE WAS A LIVE REGRESSION. mako keeps the config it
# read AT STARTUP, so linking a fresh one changes nothing about the daemon.
# A `[app-name="mux"]` rule here joins a banner's title and body onto one
# row, and with both machines' mako days old every banner rendered on three
# rows instead. The file was right and the daemon had never read it.
#
# DRIVEN THROUGH STUBS FOR BOTH HALVES, because the rule is conditional: a
# box with no mako running must stay silent rather than reporting a reload it
# did not do. `pgrep` is stubbed as well as `makoctl`, since the guard asks
# whether mako is up and the test cannot start one.
mkdir -p "$T/mstub"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\nexit 0\n' "$T/makoctl.log" \
  >"$T/mstub/makoctl"
printf '#!/bin/sh\nexit 0\n' >"$T/mstub/pgrep"
chmod +x "$T/mstub/makoctl" "$T/mstub/pgrep"
: >"$T/makoctl.log"
_o=$(env PREFIX="$T" XDG_BIN_HOME="$BIN" XDG_DATA_HOME="$SHR" \
  XDG_CONFIG_HOME="$CFG" NO_COLOR=1 PATH="$T/mstub:$PATH" \
  sh "$HERE/setup.sh" install 2>&1) || fail "install errored with mako up"
grep -qx 'reload' "$T/makoctl.log" \
  || fail "install did not reload the running mako, so it keeps whatever
config it read at startup: [$(cat "$T/makoctl.log")]"
case $_o in
  (*'reloaded the running mako'*) ;;
  (*) fail "the reload was not reported: [$_o]" ;;
esac

# AND NO MAKO MEANS NO CLAIM. `pgrep` answering 1 is a box with none running,
# which is ordinary (headless, pre-login, a container) and must not produce a
# line saying something was reloaded.
printf '#!/bin/sh\nexit 1\n' >"$T/mstub/pgrep"
: >"$T/makoctl.log"
_o=$(env PREFIX="$T" XDG_BIN_HOME="$BIN" XDG_DATA_HOME="$SHR" \
  XDG_CONFIG_HOME="$CFG" NO_COLOR=1 PATH="$T/mstub:$PATH" \
  sh "$HERE/setup.sh" install 2>&1) || fail "install errored with no mako"
[ ! -s "$T/makoctl.log" ] \
  || fail "with no mako running, install called makoctl anyway:
[$(cat "$T/makoctl.log")]"
case $_o in
  (*'reloaded the running mako'*)
    fail "with no mako running, install claimed it reloaded one: [$_o]" ;;
esac

# uninstall: the payload and links removed (no systemctl: no unit installed)
run uninstall >/dev/null 2>&1 || fail "uninstall errored"
[ -e "$BIN/mako-placement" ] && fail "mako-placement link not removed"
[ -e "$CFG/mako/config" ] && fail "mako config link not removed"
[ -e "$PAY" ] && fail "payload not removed"

pass "install + check + reinstall + uninstall"
