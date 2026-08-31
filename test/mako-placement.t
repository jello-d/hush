#!/bin/sh
# modules/tests/mako-placement - stub-driven. The placement is now AUTHORED per
# shape in shapes/<shape>/mako.conf; this asserts mako-placement reads the shape
# kanshi-autoscale reports, resolves @middle to the geometrically middle output
# (median x) on a wall, and uses the single shape's fragment verbatim otherwise.
# kanshi-autoscale, wlr-randr and makoctl are stubbed; nothing on the box.
set -eu

. "$(dirname "$0")/lib.sh"
harness_init mako-placement

MP=$HERE/bin/mako-placement
mkdir -p "$T/bin" "$T/shapes/single" "$T/shapes/triple"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/makoctl"; chmod +x "$T/bin/makoctl"

# the two shape fragments, exactly as authored in the repo
printf 'anchor=top-right\n' > "$T/shapes/single/mako.conf"
printf 'output=@middle\nanchor=bottom-center\n' > "$T/shapes/triple/mako.conf"

# kanshi-autoscale shape -> echo $STUB_SHAPE; wlr-randr -> $STUB_N outputs, out
# of x-order so the median-by-position (not row order) is exercised.
cat > "$T/bin/kanshi-autoscale" <<'EOF'
#!/bin/sh
[ "$1" = shape ] && { echo "${STUB_SHAPE:-single}"; exit 0; }
# uiprofile: emit MAKO_FONT (empty unless STUB_MAKO_FONT set) -- the lo-res
# signal mako-placement keys the density font+box append on.
[ "$1" = uiprofile ] && { printf 'MAKO_FONT=%s\n' "${STUB_MAKO_FONT:-}"
                          exit 0; }
exit 0
EOF
cat > "$T/bin/wlr-randr" <<'EOF'
#!/bin/sh
one() { printf '%s "x"\n  Enabled: yes\n  Position: %s,0\n' "$1" "$2"; }
case "${STUB_N:-3}" in
  0) : ;;                                     # no outputs live
  1) one DP-1 0 ;;
  *) one DP-3 4320; one DP-1 0; one DP-2 2160 ;;
esac
EOF
chmod +x "$T/bin/kanshi-autoscale" "$T/bin/wlr-randr"

run() {   # STUB_SHAPE / STUB_N / STUB_MAKO_FONT in env
  env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" \
    MAKO_SHAPES="$T/shapes" MAKO_ACTIVE="$T/out.active" \
    ${STUB_SHAPE:+STUB_SHAPE="$STUB_SHAPE"} ${STUB_N:+STUB_N="$STUB_N"} \
    ${STUB_MAKO_FONT:+STUB_MAKO_FONT="$STUB_MAKO_FONT"} \
    sh "$MP"
}
A=$T/out.active

# --- triple: @middle resolves to the middle output (DP-2 at x=2160) ----------
STUB_SHAPE=triple STUB_N=3 run
grep -q '^output=DP-2$' "$A" || { cat "$A"; fail "wall not centered on DP-2"; }
grep -q '^anchor=bottom-center$' "$A" || fail "wall not bottom-center"
grep -q '@middle' "$A" && fail "@middle placeholder left unresolved"

# --- single: verbatim top-right, no output pin -------------------------------
STUB_SHAPE=single STUB_N=1 run
grep -q '^anchor=top-right$' "$A" || fail "single not top-right"
grep -q '^output=' "$A" && fail "single wrongly pinned an output"

# --- triple but @middle unresolvable (no outputs) -> drop the output line -----
STUB_SHAPE=triple STUB_N=0 run
grep -q '^anchor=bottom-center$' "$A" || fail "unresolvable wall lost anchor"
grep -q '^output=' "$A" && fail "unresolvable @middle left a bad output line"

# --- density (lodpi): MAKO_FONT set -> font + a SHRUNK box appended LAST, so
# they override mako/config's own values (mako is last-wins). ------------------
STUB_SHAPE=single STUB_N=1 STUB_MAKO_FONT='Inter 11' run
grep -q '^font=Inter 11$' "$A" || fail "lodpi: mako font not appended"
grep -q '^width=320$' "$A" || fail "lodpi: mako box width not appended"
grep -q '^max-icon-size=48$' "$A" || fail "lodpi: mako icon size not appended"

# --- hidpi: MAKO_FONT empty -> NO font/box lines (base config stands) ---------
STUB_SHAPE=single STUB_N=1 run
grep -q '^font=' "$A" && fail "hidpi: mako font wrongly appended"
grep -q '^width=' "$A" && fail "hidpi: mako box wrongly appended"

pass
