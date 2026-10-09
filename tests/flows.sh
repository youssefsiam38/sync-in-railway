#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034,SC2119
# Product flows shared by the local smoke test and the live Railway smoke test. Source after lib.sh.

# security_gates -> anonymous access is refused, wrong passwords are rejected, unknown login is refused.
security_gates() {
  local jar=$TEST_TMP/wrong.jar
  api "" GET /api/app/spaces/browse/files/personal
  assert_eq "anonymous file browsing is refused" "401" "$CODE"
  api "" GET /api/app/spaces/list
  assert_eq "anonymous space listing is refused" "401" "$CODE"
  if login "$SYNC_IN_ADMIN_LOGIN" "not-the-password-$(rand)" "$jar"; then
    fail "a wrong admin password is accepted"
  else
    assert_eq "a wrong admin password is rejected" "401" "$CODE"
  fi
  if login "nobody-$(rand)" "not-the-password" "$TEST_TMP/ghost.jar"; then
    fail "an unknown login is accepted"
  else
    pass "an unknown login is rejected ($CODE)"
  fi
}

# admin_login JAR -> signs the bootstrap admin in.
admin_login() {
  if login "$SYNC_IN_ADMIN_LOGIN" "$SYNC_IN_ADMIN_PASSWORD" "$1"; then
    pass "admin signs in"
  else
    fail "admin login: HTTP $CODE"
    return 1
  fi
  api "$1" GET /api/auth/settings
  assert_eq "an authenticated session is recognised" "200" "$CODE"
}

# file_flows JAR NAME -> create a folder, upload a file, see it listed, download it byte-for-byte, delete it.
file_flows() {
  local jar=$1 dir=$2 payload=$TEST_TMP/payload.txt expect
  expect="sync-in test $(rand)"
  printf '%s\n' "$expect" >"$payload"
  api "$jar" POST "/api/app/spaces/operation/make/files/personal/$dir" -H 'Content-Type: application/json' --data '{"type":"directory"}'
  assert_eq "create folder $dir" "201" "$CODE"
  api "$jar" POST "/api/app/spaces/operation/upload/files/personal/$dir/hello.txt" -F "file=@$payload;filename=hello.txt"
  assert_eq "upload hello.txt" "201" "$CODE"
  api "$jar" GET "/api/app/spaces/browse/files/personal/$dir"
  assert_eq "folder lists the upload" "200" "$CODE"
  assert_contains "hello.txt is listed" '"name":"hello.txt"' "$BODY"
  api "$jar" GET "/api/app/spaces/operation/files/personal/$dir/hello.txt"
  assert_eq "download hello.txt" "200" "$CODE"
  assert_eq "downloaded bytes match the upload" "$expect" "$(tr -d '\r' <"$TEST_TMP/body" | head -n 1)"
  api "$jar" DELETE "/api/app/spaces/operation/files/personal/$dir"
  assert_eq "delete the test folder" "200" "$CODE"
  api "$jar" GET "/api/app/spaces/browse/files/personal"
  assert_not_contains "the test folder is gone" "\"name\":\"$dir\"" "$BODY"
}

# admin_checks JAR -> the bootstrap account is an administrator.
admin_checks() {
  api "$1" GET /api/app/spaces/admin/list
  assert_eq "the admin space list opens for the bootstrap admin" "200" "$CODE"
}
