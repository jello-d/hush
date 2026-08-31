#!/bin/sh
# tools.t - every shipped script parses: the shell tools + setup.sh by their
# shell (bash for the array/bash script, dash otherwise), the Python daemon via
# py_compile (to a scratch .pyc, so no __pycache__ lands in the tree).
. "$(dirname "$0")/lib.sh"
harness_init tools

_bad=0
for _f in "$HERE"/bin/* "$HERE"/setup.sh; do
  case "$(head -1 "$_f")" in
    *bash)
      command -v bash >/dev/null 2>&1 \
        && { bash -n "$_f" || { echo "  syntax: $_f" >&2; _bad=1; }; } ;;
    *)
      { dash -n "$_f" 2>/dev/null || sh -n "$_f" 2>/dev/null; } \
        || { echo "  syntax: $_f" >&2; _bad=1; } ;;
  esac
done
python3 -c "import py_compile,sys; py_compile.compile(sys.argv[1], \
  cfile=sys.argv[2], doraise=True)" \
  "$HERE/libexec/comms-indicator" "$T/ci.pyc" 2>/dev/null \
  || { echo "  py: libexec/comms-indicator" >&2; _bad=1; }

[ "$_bad" = 0 ] || fail "a shipped script failed its syntax check"
pass "tools + daemon parse"
