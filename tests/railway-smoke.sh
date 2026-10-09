#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2119
# Live end-to-end test against a deployed template, over HTTPS.
#
#   APP_URL=https://<domain> SYNC_IN_PASSWORD_FILE=<mode-600 file holding the admin password> \
#     STATE_FILE=/tmp/sync-in-live.name tests/railway-smoke.sh          # full run; records the folder it created
#   ... tests/railway-smoke.sh --verify                                 # after a redeploy: is it all still there?
#
# Never prints the password or cookies.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
[ -n "${APP_URL:-}" ] || { echo "set APP_URL=https://<your-domain>" >&2; exit 2; }
[ -n "${SYNC_IN_PASSWORD_FILE:-}" ] && [ -s "$SYNC_IN_PASSWORD_FILE" ] || { echo "set SYNC_IN_PASSWORD_FILE to a non-empty file" >&2; exit 2; }
APP_URL=${APP_URL%/}
: "${STATE_FILE:=$(mktemp)}"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
# shellcheck source=tests/flows.sh
. "$REPO_ROOT/tests/flows.sh"
trap 'rm -rf "$TEST_TMP"' EXIT

# The password stays in its file; lib.sh reads it with @FILE.
SYNC_IN_ADMIN_PASSWORD="@$SYNC_IN_PASSWORD_FILE"
ADMIN=$TEST_TMP/admin.jar
MODE=${1:-full}

section "edge"
assert_eq "HTTPS readiness (/healthz/ready)" "200" "$(http_code "$APP_URL/healthz/ready")"
assert_eq "HTTPS sign-in page is served" "200" "$(http_code "$APP_URL/")"
case "$APP_URL" in
  https://*) assert_eq "plain HTTP is redirected to HTTPS" "301" "$(http_code "http://${APP_URL#https://}/")" ;;
esac
api "" GET /api/app/spaces/list
assert_eq "the API refuses anonymous calls" "401" "$CODE"

section "security gates"
security_gates

section "admin"
admin_login "$ADMIN"
admin_checks "$ADMIN"
api "$ADMIN" GET /api/auth/settings
assert_eq "cookies: the session works over HTTPS" "200" "$CODE"

if [ "$MODE" = "--verify" ]; then
  DIR=$(cat "$STATE_FILE")
  [ -n "$DIR" ] || die "no marker folder in $STATE_FILE"
  section "data survived the redeploy"
  api "$ADMIN" GET "/api/app/spaces/browse/files/personal/$DIR"
  assert_eq "the marker folder is listed" "200" "$CODE"
  assert_contains "the marker file is still indexed" '"name":"marker.txt"' "$BODY"
  api "$ADMIN" GET "/api/app/spaces/operation/files/personal/$DIR/marker.txt"
  assert_eq "the marker file downloads" "200" "$CODE"
  assert_eq "its bytes survived the redeploy" "survives a redeploy" "$(tr -d '\r' <"$TEST_TMP/body" | head -n 1)"
  api "$ADMIN" DELETE "/api/app/spaces/operation/files/personal/$DIR"
  assert_eq "clean up the marker folder" "200" "$CODE"
else
  section "files"
  DIR="live-$(rand)"
  file_flows "$ADMIN" "$DIR"
  # leave one marker behind for the post-redeploy check
  api "$ADMIN" POST "/api/app/spaces/operation/make/files/personal/$DIR" -H 'Content-Type: application/json' --data '{"type":"directory"}'
  printf 'survives a redeploy\n' >"$TEST_TMP/marker.txt"
  api "$ADMIN" POST "/api/app/spaces/operation/upload/files/personal/$DIR/marker.txt" -F "file=@$TEST_TMP/marker.txt;filename=marker.txt"
  assert_eq "leave a marker file for the redeploy check" "201" "$CODE"
  printf '%s\n' "$DIR" >"$STATE_FILE"
fi

summary
