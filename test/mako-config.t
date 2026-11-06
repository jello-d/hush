#!/bin/sh
# test/mako-config.t - the shipped mako config PARSES.
#
# ITS ONLY FAILURE MODE IS SILENT AND TOTAL. mako refuses the WHOLE config on
# one bad line, so a typo in a criteria header does not cost you that rule, it
# costs you every notification on the box, and nothing says so: the daemon
# simply never draws again. A config whose failure is silent non-activation
# needs a test that loads it the way its consumer does.
#
# `mako -c` PARSES BEFORE IT CONNECTS, which is what makes this cheap and safe
# on a desktop: with a daemon already running it gets as far as "Failed to
# acquire service name" and exits, having read the file. So the assertion is
# on the PARSE message and never on the exit code, which is non-zero either
# way and says nothing.
set -eu

. "$(dirname "$0")/harness_lib"
harness_init mako-config

CFG=$HERE/share/mako/config
[ -f "$CFG" ] || fail "$CFG is missing"

command -v mako >/dev/null 2>&1 || {
  printf 'skip %s (no mako)\n' "$TEST_NAME"
  exit 0; }

# A SCRATCH HOME, seeded the way install seeds it, because the config
# include's two files by `~` path and a missing include is itself a parse
# failure. Reading the real ~/.config/mako instead made this test a question
# about the box: it passed only because placement.active happened to exist.
# The filter is RENDERED, not copied, with every kind of section the
# generator can write, so the generator's own syntax is what gets parsed.
# makoctl is stubbed and the runtime dir is scratch: a render reloads mako
# and leaves a warning file, and neither may reach the live session.
_H=$T/home
mkdir -p "$_H/.config/mako" "$_H/.config/hush" "$T/stub" "$T/run"
cp "$HERE/share/mako/default.conf" "$_H/.config/mako/placement.active"
printf '#!/bin/sh\nexit 0\n' > "$T/stub/makoctl"; chmod +x "$T/stub/makoctl"
printf '%s\n' 'work-from=origin' "origin-command=printf 'titan\\tx\\n'" \
  'allow=mux' 'allow=Google Chrome' 'allow-critical=yes' \
  > "$_H/.config/hush/config"
env PATH="$T/stub:$PATH" XDG_RUNTIME_DIR="$T/run" \
  XDG_CONFIG_HOME="$_H/.config" sh "$HERE/bin/dnd-comms-toggle" render \
  || fail "the filter did not render"
grep -qxF '[mode=hush-work app-name="titan" group-index=0]' \
  "$_H/.config/mako/filter.active" \
  || fail "the rendered filter carries no work origin, so its syntax is
not what this test parses: $(cat "$_H/.config/mako/filter.active")"

# BOUNDED, because on a box with no notification daemon and a live compositor
# this would otherwise START one and sit there. Five seconds is far longer
# than a parse and the output is all we read.
_try() {   # <config> -> its output
  HOME=$_H timeout 5 mako -c "$1" >"$T/out" 2>&1 || true
  cat "$T/out"
}

case $(_try "$CFG") in
  (*'Failed to parse'*)
    fail "the shipped mako config does not parse, so mako would refuse ALL
of it and the box would go quiet with nothing said:
$(sed 's/^/  /' "$T/out")" ;;
esac

# AND THE DETECTOR IS PROVEN, or a parse check that stopped working would
# report a clean config for ever. An unterminated criteria header is the
# shape a hand-edited rule actually fails in.
printf 'format=<b>%%s</b>\n[app-name=\n' >"$T/bad.conf"
case $(_try "$T/bad.conf") in
  (*'Failed to parse'*) ;;
  (*) fail "a deliberately broken config was accepted, so the check above
proves nothing: [$(cat "$T/out")]" ;;
esac

# THE mux RULES ARE THE REASON THIS FILE EXISTS, so they are named rather
# than merely covered by the parse. Both of them: mako has a BUILT-IN
# `[grouped]` criteria that swaps in its own format and hides all but the
# first of a group, so without the second rule a second banner silently
# reverts to a two-row title. One assertion per rule, because a check for
# "mux is mentioned" passes with either one missing.
grep -qxF '[app-name="mux"]' "$CFG" \
  || fail "the mux rule is gone, so its banners go back to a two-row title"
grep -qxF '[app-name="mux" grouped]' "$CFG" \
  || fail "the GROUPED mux rule is gone, so the shape changes the moment a
second session speaks and only the first banner looks right"

# A RELAYED CHROME KEEPS ITS LOOK. A relay posts under its own app name and
# moves "Google Chrome" into the summary, and Chrome sends a calendar reminder
# as CRITICAL, so without this rule every relayed reminder is painted red by
# [urgency=high] (measured: the rule is the difference between the two).
grep -qxF '[summary~="^Google Chrome: " actionable=true]' "$CFG" \
  || fail "the relayed-Chrome rule is gone, so relayed calendar reminders
render red as critical alerts"

# AND BOTH JOIN SUMMARY AND BODY WITH A SPACE, which is the entire point: the
# host arrives as the body's first line, so a `\n` here would put it back on
# its own row and undo the change these rules exist for.
for _r in '[app-name="mux"]' '[app-name="mux" grouped]'; do
  _fmt=$(awk -v r="$_r" '$0==r {f=1; next} f && /^format=/ {print; exit}
    f && /^\[/ {exit}' "$CFG")
  [ -n "$_fmt" ] || fail "$_r has no format= line of its own"
  case $_fmt in
    (*'%s</b></big> '*) ;;
    (*) fail "$_r does not join the title and body with a SPACE, so mux's
host goes back to its own row: [$_fmt]" ;;
  esac
done

pass
