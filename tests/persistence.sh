#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2119
# Persistence test: data written before a full recreate survives it. Covers the files volume (/app/data),
# the MariaDB volume (the account and the file index), and that the bootstrap does not run twice.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
# shellcheck source=tests/flows.sh
. "$REPO_ROOT/tests/flows.sh"

ADMIN=$TEST_TMP/admin.jar
DIR="persist-$(rand)"
cleanup() { compose down -v --remove-orphans >/dev/null 2>&1 || true; rm -rf "$TEST_TMP"; }
trap cleanup EXIT

section "seed"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_app || die "Sync-in never became ready"
admin_login "$ADMIN" || die "admin cannot sign in"
api "$ADMIN" POST "/api/app/spaces/operation/make/files/personal/$DIR" -H 'Content-Type: application/json' --data '{"type":"directory"}'
assert_eq "create the marker folder" "201" "$CODE"
printf 'survives a redeploy\n' >"$TEST_TMP/marker.txt"
api "$ADMIN" POST "/api/app/spaces/operation/upload/files/personal/$DIR/marker.txt" -F "file=@$TEST_TMP/marker.txt;filename=marker.txt"
assert_eq "upload the marker file" "201" "$CODE"

section "full recreate (containers removed, volumes kept)"
compose down >/dev/null 2>&1 || die "compose down failed"
compose up -d >/dev/null 2>&1 || die "compose up after down failed"
wait_for_app || die "Sync-in never came back"
logs=$(compose logs --no-color sync_in 2>&1)
# .init lives in the container layer (/app), not the volume, so a new container re-runs the bootstrap.
# That is safe: migrations are idempotent and create-user skips an existing login. Assert that, not a single run.
assert_contains "the new container re-runs the bootstrap safely" "already exists" "$logs"
assert_not_contains "the admin is not created a second time" "created successfully" "$logs"

section "data"
if login "$SYNC_IN_ADMIN_LOGIN" "$SYNC_IN_ADMIN_PASSWORD" "$ADMIN"; then pass "the admin account survived (MariaDB volume)"; else fail "admin login after recreate: HTTP $CODE"; fi
api "$ADMIN" GET "/api/app/spaces/browse/files/personal/$DIR"
assert_eq "the marker folder is listed" "200" "$CODE"
assert_contains "the marker file is still indexed" '"name":"marker.txt"' "$BODY"
api "$ADMIN" GET "/api/app/spaces/operation/files/personal/$DIR/marker.txt"
assert_eq "the marker file downloads" "200" "$CODE"
assert_eq "its bytes survived the recreate" "survives a redeploy" "$(tr -d '\r' <"$TEST_TMP/body" | head -n 1)"
assert_eq "the data volume holds the marker on disk" "1" "$(compose exec -T sync_in sh -c "find /app/data -name marker.txt | wc -l" | tr -d '\r ')"

summary
