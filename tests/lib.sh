#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034,SC2120
# Shared helpers for sync-in-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, counts, and pass/fail results are printed.

: "${APP_URL:=http://127.0.0.1:${SYNC_IN_TEST_PORT:-18080}}"
: "${TEST_TIMEOUT:=300}"
: "${SYNC_IN_ADMIN_LOGIN:=${SYNC_IN_TEST_ADMIN_LOGIN:-admin}}"
: "${SYNC_IN_ADMIN_PASSWORD:=${SYNC_IN_TEST_ADMIN_PASSWORD:-local-test-only-admin-password}}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
chmod 700 "$TEST_TMP"
export TEST_TMP
_PASS=0; _FAIL=0
CODE=""; BODY=""

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -qF -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_match() { if grep -qE -- "$2" <<<"$3"; then pass "$1"; else fail "$1: no match for [$2]"; fi; }
assert_not_contains() { if grep -qF -- "$2" <<<"$3"; then fail "$1: found forbidden value"; else pass "$1"; fi; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@" || true; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url")
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

wait_for_app() { wait_for_code "$APP_URL/healthz/ready" 200 "${1:-$TEST_TIMEOUT}"; }

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }

rand() { head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# Login body is written to a private file and sent with --data-binary @file, never on argv.
# login LOGIN PASSWORD JAR -> 0 when the server answers 201 and sets the access cookie.
login() {
  local jar=$3
  rm -f "$jar"
  # A password of the form @FILE is read from that file, so the secret never reaches argv.
  ( umask 077
    if [[ "$2" == @* ]]; then
      jq -cn --arg l "$1" --rawfile p "${2#@}" '{login:$l,password:($p|rtrimstr("\n"))}' >"$TEST_TMP/login.json"
    else
      jq -cn --arg l "$1" --arg p "$2" '{login:$l,password:$p}' >"$TEST_TMP/login.json"
    fi )
  CODE=$(curl -s -o "$TEST_TMP/login.out" -w '%{http_code}' --max-time 60 -c "$jar" \
    -H 'Content-Type: application/json' --data-binary "@$TEST_TMP/login.json" "$APP_URL/api/auth/login" || echo 000)
  rm -f "$TEST_TMP/login.json" "$TEST_TMP/login.out"
  [ "$CODE" = "201" ] && grep -q 'sync-in-access' "$jar"
}

# csrf_header JAR -> prints the "sync-in-csrf: <value>" header line from the jar's csrf cookie.
csrf_header() { printf 'sync-in-csrf: %s' "$(awk '$6=="sync-in-csrf"{print $7}' "$1")"; }

# api JAR METHOD PATH [curl args...] -> sets CODE and BODY. JAR may be "" (anonymous). Adds the CSRF header when a jar is set.
api() {
  local jar=$1 method=$2 path=$3 out
  shift 3
  local args=(-s -o "$TEST_TMP/body" -w '%{http_code}' --max-time 60 -X "$method")
  if [ -n "$jar" ]; then args+=(-b "$jar" -c "$jar" -H "$(csrf_header "$jar")"); fi
  CODE=$(curl "${args[@]}" "$@" "$APP_URL$path" || echo 000)
  BODY=$(tr -d '\000' <"$TEST_TMP/body" 2>/dev/null || true)
}
