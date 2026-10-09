#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2119
# Local end-to-end smoke test against a fresh compose stack (the stock images are pulled by digest).
# Covers: the admin bootstrap from env, the database flags, auth gates, admin sign-in, file flows, and
# that the bootstrap does not run twice.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
# shellcheck source=tests/flows.sh
. "$REPO_ROOT/tests/flows.sh"

ADMIN=$TEST_TMP/admin.jar
cleanup() { [ "${KEEP_STACK:-0}" = 1 ] || compose down -v --remove-orphans >/dev/null 2>&1 || true; rm -rf "$TEST_TMP"; }
trap cleanup EXIT

section "start-up"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_app || { compose logs --tail 80 >&2; die "Sync-in never became ready"; }
pass "/healthz/ready answers 200"
logs=$(compose logs --no-color sync_in 2>&1)
assert_contains "the migrations ran" "Database migrations applied successfully" "$logs"
assert_contains "the admin account was created" "Administrator *$SYNC_IN_ADMIN_LOGIN* created successfully" "$logs"
assert_not_contains "the admin password never reaches the logs" "$SYNC_IN_ADMIN_PASSWORD" "$logs"
assert_contains "the server is listening on 8080" "Server listening at http://0.0.0.0:8080" "$logs"
assert_not_contains "no event-scheduler fallback (the DB flag was applied)" "Fallback to internal scheduler" "$logs"

section "database"
db_logs=$(compose logs --no-color mariadb 2>&1)
assert_eq "MariaDB runs with the event scheduler on" "ON" "$(compose exec -T mariadb sh -c 'mariadb -N -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT @@event_scheduler"' | tr -d '\r')"
assert_eq "the app database exists" "sync_in" "$(compose exec -T mariadb sh -c 'mariadb -N -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME=\"sync_in\""' | tr -d '\r')"
assert_eq "the packet limit is 1G" "1073741824" "$(compose exec -T mariadb sh -c 'mariadb -N -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT @@max_allowed_packet"' | tr -d '\r')"
assert_not_contains "no database errors at boot" "ERROR" "$db_logs"

section "container"
in_c() { compose exec -T sync_in sh -c "$1" | tr -d '\r'; }
assert_eq "the data path is a mounted volume" "yes" "$(in_c 'grep -q " /app/data " /proc/mounts && echo yes')"
assert_eq "the init marker is written" "yes" "$(in_c 'test -f /app/.init && echo yes')"
assert_eq "the server runs as the unprivileged user" "8888" "$(in_c 'stat -c %u /app/data')"
# The image's HEALTHCHECK has a 60 s start period, so poll for it rather than sampling once.
health=starting
for _ in $(seq 1 40); do
  health=$(docker inspect -f '{{.State.Health.Status}}' "$(compose ps -q sync_in)" 2>/dev/null || echo unknown)
  [ "$health" = healthy ] && break
  sleep 3
done
assert_eq "the image healthcheck reports healthy" "healthy" "$health"

section "security gates"
security_gates

section "admin"
admin_login "$ADMIN"
admin_checks "$ADMIN"

section "files"
file_flows "$ADMIN" "smoke-$(rand)"

section "restart"
compose restart sync_in >/dev/null 2>&1 || die "restart failed"
sleep 2
wait_for_app || die "Sync-in never came back"
logs=$(compose logs --no-color sync_in 2>&1)
assert_eq "the bootstrap ran once (no second database wait)" "1" "$(grep -c 'Waiting for database to be ready' <<<"$logs")"
assert_eq "exactly one admin creation in the whole log" "1" "$(grep -c 'created successfully' <<<"$logs")"
if login "$SYNC_IN_ADMIN_LOGIN" "$SYNC_IN_ADMIN_PASSWORD" "$ADMIN"; then pass "admin signs in after a restart"; else fail "admin login after restart: HTTP $CODE"; fi

summary
