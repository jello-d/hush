# test/lib.sh - a tiny harness for hush's tests, sourced by each *.t.
# Call `harness_init <name>`: sets HERE (the repo root), a private scratch dir T
# (removed on exit), and fail/pass. POSIX sh; nothing outside T is touched.
harness_init() {   # <name>
  TEST_NAME=$1
  HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
  T=$(mktemp -d)
  trap 'rm -rf "$T"' EXIT INT TERM
}
pass() { printf 'ok   %s%s\n' "$TEST_NAME" "${1:+ ($1)}"; }
fail() { printf 'FAIL %s: %s\n' "$TEST_NAME" "$1" >&2; exit 1; }
