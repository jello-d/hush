#!/bin/sh
# test/filter.t - dnd-comms-toggle's generated filter and its state changes,
# with makoctl STUBBED (every call recorded) and a scratch config and runtime
# dir, so nothing reaches the live mako. What mako then DOES with the filter
# is filter-live.t's question; this one asserts what is written and called.
set -eu

. "$(dirname "$0")/harness_lib"
harness_init filter

mkdir -p "$T/stub" "$T/run" "$T/cfg/hush"
cat > "$T/stub/makoctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
EOF
chmod +x "$T/stub/makoctl"
F=$T/cfg/mako/filter.active
W=$T/run/dnd-comms-warn
CONF=$T/cfg/hush/config
tog() {   # <args...> -> stdout+stderr in $T/out, rc in $RC
  RC=0
  env PATH="$T/stub:$PATH" XDG_RUNTIME_DIR="$T/run" \
    XDG_CONFIG_HOME="$T/cfg" sh "$HERE/bin/dnd-comms-toggle" "$@" \
    > "$T/out" 2>&1 || RC=$?
}
has() {   # <criteria> : the filter carries exactly this section header
  grep -qxF "$1" "$F"
}
shown() {   # <mode> <criteria> : un-hidden, in BOTH grouping halves
  has "[mode=$1 $2 !grouped]" && has "[mode=$1 $2 group-index=0]"
}

# --- the shipped default: apps mode, Slack is work -------------------------
tog render
[ "$RC" = 0 ] || fail "render with no user config failed: $(cat "$T/out")"
has '[mode=hush-none]' && has '[mode=hush-work]' \
  || fail "a mode is missing its hide-all: $(cat "$F")"
shown hush-work 'app-name="Slack"' \
  || fail "the shipped default does not show Slack in work"
has '[mode=hush-none app-name="Slack" !grouped]' \
  && fail "work apps leaked into none"
[ ! -e "$W" ] || fail "a clean render left a warning: $(cat "$W")"

# --- origin: work is whatever the command names (first field) -------------
printf 'titan\tjello-titan\t997\nacme\n' > "$T/enclaves"
cat > "$CONF" <<EOF
# a comment, and a blank line

work-from=origin
origin-command=cat $T/enclaves
allow=mux
allow = Google Chrome
allow-critical=yes
EOF
tog render
[ "$RC" = 0 ] || fail "origin render failed: $(cat "$T/out")"
shown hush-work 'app-name="titan"' && shown hush-work 'app-name="acme"' \
  || fail "the origins are not shown in work: $(cat "$F")"
has '[mode=hush-work app-name="jello-titan" !grouped]' \
  && fail "a field past the first was taken as an origin"
for _m in hush-work hush-none; do
  shown "$_m" 'app-name="mux"' && shown "$_m" 'app-name="Google Chrome"' \
    && shown "$_m" 'urgency=critical' \
    || fail "the allowlist is incomplete in $_m: $(cat "$F")"
done
grep -q 'Slack' "$F" && fail "apps-mode names leaked into origin mode"
# Order is the whole mechanism: the hide-all must come BEFORE its exceptions.
_hide=$(grep -nxF '[mode=hush-work]' "$F" | cut -d: -f1)
_ex=$(grep -nF '[mode=hush-work app-name="titan"' "$F" | head -1 | cut -d: -f1)
[ "$_hide" -lt "$_ex" ] || fail "work's hide-all comes after an exception"

# --- state changes: clear every mode (legacy too), then add one -------------
: > "$T/calls"
tog set work
[ "$RC" = 0 ] && [ "$(cat "$T/run/dnd-comms-state")" = work ] \
  || fail "set work failed: $(cat "$T/out")"
for _m in hush-work hush-none dnd-personal dnd-comms; do
  grep -qxF "mode -r $_m" "$T/calls" || fail "set did not clear mode $_m"
done
[ "$(tail -n 1 "$T/calls")" = "mode -a hush-work" ] \
  || fail "set work did not end by adding hush-work: $(cat "$T/calls")"
tog toggle
[ "$(cat "$T/run/dnd-comms-state")" = none ] \
  && [ "$(tail -n 1 "$T/calls")" = "mode -a hush-none" ] \
  || fail "toggle from work did not reach none"
: > "$T/calls"
tog toggle
[ "$(cat "$T/run/dnd-comms-state")" = all ] \
  || fail "toggle from none did not reach all"
grep -q '^mode -a' "$T/calls" && fail "all added a mode: $(cat "$T/calls")"
tog set bogus
[ "$RC" = 2 ] || fail "an unknown state was accepted (rc $RC)"
tog
[ "$(cat "$T/out")" = all ] || fail "a bare call did not print the state"

# --- an unknown work set: work HIDES NOTHING, and says so ------------------
_unknown() {   # <label>
  tog render
  [ "$RC" = 0 ] || fail "$1: render failed"
  has '[mode=hush-work]' \
    && fail "$1: work still hides everything with no work set known"
  has '[mode=hush-none]' || fail "$1: none stopped filtering too"
  [ -s "$W" ] || fail "$1: nothing was left for the tray icon to show"
  grep -q 'hides nothing' "$T/out" || fail "$1: nothing said on stderr"
}
sed -i "s|^origin-command=.*|origin-command=cat $T/enclaves; exit 1|" "$CONF"
_unknown "a failing command"
sed -i "s|^origin-command=.*|origin-command=true|" "$CONF"
_unknown "a command naming nothing"
sed -i "/^origin-command=/d" "$CONF"
_unknown "no command at all"
printf 'ev"il\n' > "$T/enclaves"
echo "origin-command=cat $T/enclaves" >> "$CONF"
_unknown "an origin that would break mako's quoting"

# ... and the warning clears once it answers again
printf 'titan\n' > "$T/enclaves"
tog render
[ ! -e "$W" ] || fail "the warning outlived its cause"

# --- an unreadable config keeps the last good filter, and says so ---------
cp "$F" "$T/good"
echo 'alow=typo' >> "$CONF"
tog set work
[ "$RC" = 0 ] || fail "a config typo blocked the state change"
cmp -s "$F" "$T/good" || fail "a config typo replaced the filter"
grep -q 'alow=typo' "$W" || fail "the typo was not named for the tray icon"
sed -i '$d' "$CONF"
echo 'allow=ba"d' >> "$CONF"
tog render
cmp -s "$F" "$T/good" || fail "a name breaking mako's quoting was written"
# with NO filter yet, one that hides nothing is written: mako will not start
# with its include missing
rm -f "$F"
tog render
[ -e "$F" ] || fail "no filter at all was left, so mako cannot start"
grep -q '^\[' "$F" && fail "a filter from an unreadable config filters"

# --- check: current, or stale, and it writes nothing ------------------------
sed -i '/ba"d/d' "$CONF"   # the case above left its bad name behind
tog render
tog check
[ "$RC" = 0 ] || fail "check called a fresh render stale: $(cat "$T/out")"
cp "$F" "$T/before"
echo 'allow=vigilance' >> "$CONF"
tog check
[ "$RC" = 1 ] && grep -q stale "$T/out" \
  || fail "check missed a config changed after the render (rc $RC)"
cmp -s "$F" "$T/before" || fail "check wrote the filter"
tog render
tog check
[ "$RC" = 0 ] || fail "check still stale after a render: $(cat "$T/out")"
printf 'titan\nnewco\n' > "$T/enclaves"
tog check
[ "$RC" = 1 ] || fail "check missed a work set that changed (rc $RC)"
tog render
mv "$F" "$T/gone"
tog check
[ "$RC" = 1 ] || fail "check passed with no filter at all"
mv "$T/gone" "$F"

# --- probe: each class titled with what it must do in THIS state ------------
printf '#!/bin/sh\nprintf "%%s|%%s|%%s\\n" "$2" "$4" "$5" >> "%s"\n' \
  "$T/sent" > "$T/stub/notify-send"
chmod +x "$T/stub/notify-send"
_probe_in() {   # <state> -> $T/sent
  echo "$1" > "$T/run/dnd-comms-state"; : > "$T/sent"; tog probe
  [ "$RC" = 0 ] || fail "probe failed in $1: $(cat "$T/out")"
}
_says() {   # <app> <SHOWN|HIDDEN>
  grep -q "^$1|.*should be $2\$" "$T/sent" \
    || fail "probe in $_ps: $1 should say $2: $(cat "$T/sent")"
}
_ps=work; _probe_in work
_says hush-probe-personal HIDDEN; _says mux SHOWN
_says hush-probe-critical SHOWN; _says titan SHOWN
_ps=none; _probe_in none
_says hush-probe-personal HIDDEN; _says titan HIDDEN; _says mux SHOWN
_ps=all; _probe_in all
_says hush-probe-personal SHOWN; _says titan SHOWN
grep -q 'work run titan' "$T/out" || fail "probe did not say how to send
through the relay"
# an unknown work set: work hides nothing, so probe must promise that
sed -i "s|^origin-command=.*|origin-command=false|" "$CONF"
_ps="work, unknown set"; _probe_in work
_says hush-probe-personal SHOWN

pass "apps + origin + allowlist + failure paths + check + probe"
