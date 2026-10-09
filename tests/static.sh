#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2119
# Static validation: syntax, shellcheck, compose shape, image pins and secret hygiene. No pulls, no containers.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
trap 'rm -rf "$TEST_TMP"' EXIT

section "syntax"
for f in tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck"; else fail "shellcheck"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config -q; then pass "compose config"; else fail "compose config"; fi
cfg=$(docker compose -f compose.yaml config --format json)
assert_eq "two services" "mariadb sync_in" "$(jq -r '[.services | keys[]] | sort | join(" ")' <<<"$cfg")"
assert_eq "the app publishes 8080 only to loopback" "127.0.0.1" "$(jq -r '[.services.sync_in.ports[]? | .host_ip] | join(" ")' <<<"$cfg")"
assert_eq "the app listens on 8080" "8080" "$(jq -r '[.services.sync_in.ports[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "the database is not published" "" "$(jq -r '[.services.mariadb.ports[]?] | join(" ")' <<<"$cfg")"
assert_eq "the app has one volume, at /app/data" "/app/data" "$(jq -r '[.services.sync_in.volumes[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "the database has one volume, at /var/lib/mysql" "/var/lib/mysql" "$(jq -r '[.services.mariadb.volumes[]? | .target] | join(" ")' <<<"$cfg")"

section "images"
assert_match "the app image is pinned by tag and digest" '^syncin/server:[0-9.]*@sha256:[0-9a-f]{64}$' "$(jq -r '.services.sync_in.image' <<<"$cfg")"
assert_match "the database image is pinned by tag and digest" '^mariadb:11\.[0-9]*@sha256:[0-9a-f]{64}$' "$(jq -r '.services.mariadb.image' <<<"$cfg")"
assert_eq "no entrypoint override (upstream entrypoint runs, no wrapper)" "null" "$(jq -r '.services.sync_in.entrypoint' <<<"$cfg")"

section "secrets hygiene"
mapfile -t tracked < <(git ls-files 2>/dev/null | grep . || find . -type f -not -path './.git/*' -not -path './test-output/*')
if [ "${#tracked[@]}" -gt 0 ] && grep -lE '(sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "${tracked[@]}" 2>/dev/null; then
  fail "a credential-shaped string is in the repository"
else
  pass "no credential-shaped strings in the repository"
fi

summary
