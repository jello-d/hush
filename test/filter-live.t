#!/bin/sh
# test/filter-live.t - what a REAL mako shows in each state, with the SHIPPED
# config and a filter dnd-comms-toggle renders, driven by dnd-comms-toggle
# itself. filter.t asserts what is written; this asserts what mako does with
# it, which is the half that rests on mako's matching order and its grouping.
#
# A headless sway, a PRIVATE bus and a private mako. FAIL CLOSED: the runtime
# dir is scratch and every display variable is unset, so nothing started here
# can find the live desktop or the session bus. Visibility is read from
# PIXELS, because mako still LISTS a notification it hides (measured).
#
# Skips where the tools are missing (sway, mako, grim, gdbus, dbus-daemon,
# python3 with Pillow). Takes about 20 seconds.
set -u

. "$(dirname "$0")/harness_lib"
harness_init filter-live

for _c in sway mako makoctl grim gdbus dbus-daemon python3; do
  command -v "$_c" >/dev/null 2>&1 || {
    printf 'skip %s (no %s)\n' "$TEST_NAME" "$_c"; exit 0; }
done
python3 -I -c 'import PIL' 2>/dev/null || {
  printf 'skip %s (no Pillow)\n' "$TEST_NAME"; exit 0; }

mkdir -m 0700 "$T/run"
mkdir -p "$T/home/.config/mako" "$T/home/.config/hush"
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config"
export XDG_RUNTIME_DIR="$T/run"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$T/run/bus"
unset WAYLAND_DISPLAY DISPLAY SWAYSOCK WAYFIRE_SOCKET
: > "$T/pids"
# Every daemon is started directly (never a shell function), so each pid in
# the list IS the process; the scratch path stays baked in (harness_lib).
_stop() { while read -r _p; do kill "$_p" 2>/dev/null; done < "$T/pids"; }
# shellcheck disable=SC2064
trap "_stop; rm -rf $HARNESS_RM" EXIT INT TERM
waitfor() {   # <tenths> <test...>
  _n=$1; shift
  while [ "$_n" -gt 0 ]; do "$@" && return 0; _n=$((_n - 1)); sleep 0.1; done
  return 1
}

dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --nofork \
  --nopidfile > "$T/dbus.log" 2>&1 &
echo $! >> "$T/pids"
: > "$T/sway.cfg"
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
  sway -c "$T/sway.cfg" > "$T/sway.log" 2>&1 &
echo $! >> "$T/pids"
waitfor 50 test -S "$T/run/wayland-1" \
  || fail "headless sway gave no display: $(tail -n 3 "$T/sway.log")"
export WAYLAND_DISPLAY=wayland-1
waitfor 50 test -S "$T/run/bus" || fail "the private bus did not start"

# THE SHIPPED CONFIG, made legible to a pixel probe and nothing else: every
# background is one opaque red, borders off, no timeout. Its sections and its
# include positions are untouched, which is what is under test.
sed -e 's/^background-color=.*/background-color=#ff0000ff/' \
  -e 's/^border-size=.*/border-size=0/' \
  -e 's/^default-timeout=.*/default-timeout=0/' \
  "$HERE/share/mako/config" > "$T/mako.conf"
printf 'anchor=top-left\nmargin=6\n' \
  > "$T/home/.config/mako/placement.active"
printf '%s\n' 'work-from=origin' "origin-command=printf 'titan\\tx\\n'" \
  'allow=mux' 'allow-critical=yes' > "$T/home/.config/hush/config"
TOG="$HERE/bin/dnd-comms-toggle"
sh "$TOG" render || fail "the filter did not render"

mako -c "$T/mako.conf" > "$T/mako.log" 2>&1 &
echo $! >> "$T/pids"
waitfor 50 makoctl mode >/dev/null 2>&1 \
  || fail "mako did not start: $(tail -n 3 "$T/mako.log")"

send() {   # <app> <urgency 0-2>
  gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify "$1" 0 "" s b '[]' \
    "{'urgency': <byte $2>}" 0 >/dev/null
}
visible() {   # -> how many separate notifications are on screen
  grim -g "20,0 1x700" "$T/strip.png" 2>/dev/null || { echo grim; return; }
  python3 -I -c 'import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
n, prev = 0, False
for y in range(im.height):
    p = im.getpixel((0, y))
    red = p[0] > 200 and p[1] < 60 and p[2] < 60
    n += red and not prev
    prev = red
print(n)' "$T/strip.png"
}
BAD=
expect() {   # <state> <label> <want> <app urgency>...
  _st=$1 _l=$2 _w=$3; shift 3
  makoctl dismiss --all >/dev/null 2>&1; sleep 0.3
  while [ $# -ge 2 ]; do send "$1" "$2"; shift 2; done
  sleep 0.7
  _got=$(visible)
  [ "$_got" = "$_w" ] || BAD="$BAD
  $_st: $_l shows $_got, want $_w"
}

# THE POSITIVE CONTROL FIRST: with no filter active, everything shows, and
# two different apps make two boxes, so the probe can see a second one.
sh "$TOG" set all || fail "set all failed"
expect all "Signal" 1 Signal 1
expect all "two apps" 2 Signal 1 mux 1
for _st in work none; do
  sh "$TOG" set "$_st" 2>"$T/err" || fail "set $_st failed: $(cat "$T/err")"
  case $_st in work) _titan=1 ;; *) _titan=0 ;; esac
  expect "$_st" "Signal (personal)" 0 Signal 1
  expect "$_st" "titan (work origin)" "$_titan" titan 1
  expect "$_st" "mux (allowed)" 1 mux 1
  expect "$_st" "critical Signal (allowed)" 1 Signal 2
  # an allowed app's GROUP still collapses to one box: the un-hide must not
  # undo mako's own [grouped] hiding
  expect "$_st" "two mux (one group)" 1 mux 1 mux 1
done
sh "$TOG" set all
expect all "Signal, after work and none" 1 Signal 1

[ -z "$BAD" ] || fail "mako showed the wrong thing:$BAD"
pass "all / work / none against a real mako"
