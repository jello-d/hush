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

# BOUNDED, because on a box with no notification daemon and a live compositor
# this would otherwise START one and sit there. Five seconds is far longer
# than a parse and the output is all we read.
_try() {   # <config> -> its output
  timeout 5 mako -c "$1" >"$T/out" 2>&1 || true
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
