#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fake_podman="$test_dir/podman"
fake_sudo="$test_dir/sudo"
call_log="$test_dir/calls"

cat >"$fake_podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$CALL_LOG"

if [ "${1:-}" = login ] && [ "${2:-}" = --get-login ]; then
  [ "${EXISTING_LOGIN:-0}" = 1 ]
  exit
fi

if [ "${1:-}" = login ]; then
  password="$(cat)"
  [ "$password" = "${EXPECTED_PASSWORD:-}" ]
  [ "$*" = "${EXPECTED_LOGIN_ARGS:-}" ]
  exit
fi

exit 2
EOF
chmod +x "$fake_podman"

cat >"$fake_sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
chmod +x "$fake_sudo"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_call_log() {
  local expected="$1"
  local actual
  actual="$(cat "$call_log")"
  [ "$actual" = "$expected" ] || fail "expected call '$expected', got '$actual'"
}

: >"$call_log"
CALL_LOG="$call_log" EXISTING_LOGIN=1 \
  "$project_dir/scripts/registry-login.sh" ghcr.io/oci-native/archlinux "$fake_podman"
assert_call_log 'login --get-login ghcr.io'
printf 'ok - existing Podman credentials are reused\n'

: >"$call_log"
CALL_LOG="$call_log" EXISTING_LOGIN=1 \
  "$project_dir/scripts/registry-login.sh" ghcr.io/oci-native/archlinux "$fake_sudo" "$fake_podman"
assert_call_log 'login --get-login ghcr.io'
printf 'ok - multi-word Podman commands are preserved\n'

: >"$call_log"
CALL_LOG="$call_log" EXPECTED_PASSWORD=token EXPECTED_LOGIN_ARGS='login ghcr.io --username octocat --password-stdin' \
  GHCR_USERNAME=octocat GHCR_TOKEN=token \
  "$project_dir/scripts/registry-login.sh" ghcr.io/oci-native/archlinux "$fake_podman"
assert_call_log $'login --get-login ghcr.io\nlogin ghcr.io --username octocat --password-stdin'
printf 'ok - GHCR environment credentials are used when needed\n'

: >"$call_log"
if missing_output="$(CALL_LOG="$call_log" "$project_dir/scripts/registry-login.sh" ghcr.io/oci-native/archlinux "$fake_podman" 2>&1)"; then
  fail 'missing credentials should fail'
fi
[[ "$missing_output" == *'Log in with `podman login ghcr.io`, or set GHCR_USERNAME and GHCR_TOKEN.'* ]] || \
  fail 'missing credential guidance is incomplete'
assert_call_log 'login --get-login ghcr.io'
printf 'ok - missing credentials produce actionable guidance\n'

: >"$call_log"
CALL_LOG="$call_log" "$project_dir/scripts/registry-login.sh" ttl.sh/oci-native/archlinux "$fake_podman"
[ ! -s "$call_log" ] || fail 'ttl.sh should not trigger a login'
printf 'ok - anonymous ttl.sh pushes skip login\n'
