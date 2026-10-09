# Railway template configuration

The template's exact configuration. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Sync-in |
| Code | `sync-in` |
| Template id | `dc96ea6f-8d77-49a1-a323-986be99a87de` |
| Deploy URL | https://railway.com/deploy/sync-in |
| Category | Storage |
| Card description | Self-hosted file sync and sharing with MariaDB. Admin from env, no sign-up. |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

Generated values use Railway's `secret()` function: `hexN` is `${{secret(N, "abcdef0123456789")}}` and `alnumN` is
`${{secret(N, "a-zA-Z0-9")}}` spelled out. Alphanumeric passwords are used wherever a value is embedded in a
connection URL, so nothing needs percent-encoding. Images are referenced by tag, because the template generator
rejects digests; `UPSTREAM.md` records the digests.

## Services

### `db`

| Field | Value |
|---|---|
| Source | `mariadb:11.8@sha256:6422478cb8e159f080fb1d8ccf65101e26fe51385787fde7d16c3b165a331f15` |
| Public domain | none |
| Volume | `/var/lib/mysql` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `MARIADB_ROOT_PASSWORD` | generated, alnum40 |
| `MARIADB_DATABASE` | `sync_in` |

### `server`

| Field | Value |
|---|---|
| Source | `syncin/server:2.5.2@sha256:c6a618f955601722d033057f489380618310eda895f1eb1ea755570bee25fd40` |
| Public domain | target port 8080 |
| Volume | `/app/data` |
| Healthcheck | `/healthz/ready`, timeout from `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `INIT_ADMIN` | `true` |
| `INIT_ADMIN_LOGIN` | `admin` |
| `INIT_ADMIN_PASSWORD` | generated, alnum24 |
| `SYNCIN_SERVER_PUBLICURL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| `SYNCIN_SERVER_PORT` | `8080` |
| `SYNCIN_MYSQL_URL` | `mysql://root:${{db.MARIADB_ROOT_PASSWORD}}@${{db.RAILWAY_PRIVATE_DOMAIN}}:3306/${{db.MARIADB_DATABASE}}` |
| `SYNCIN_AUTH_ENCRYPTIONKEY` | generated, alnum64 |
| `SYNCIN_AUTH_TOKEN_ACCESS_SECRET` | generated, alnum64 |
| `SYNCIN_AUTH_TOKEN_REFRESH_SECRET` | generated, alnum64 |
| `TZ` | `UTC` |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `300` |
| `SYNCIN_MAIL_HOST` | optional, unset |
| `SYNCIN_MAIL_PORT` | optional, unset |
| `SYNCIN_MAIL_SENDER` | optional, unset |
| `SYNCIN_MAIL_AUTH_USER` | optional, unset |
| `SYNCIN_MAIL_AUTH_PASS` | optional, unset |
| `SYNCIN_AUTH_PROVIDER` | optional, unset |
| `SYNCIN_LOGGER_LEVEL` | optional, unset |

## Notes

Stock upstream images, pinned by digest (see `UPSTREAM.md`). The app connects to MariaDB as `root` (upstream runs `SET GLOBAL event_scheduler`, which needs SUPER). Full-text tuning from upstream's compose (`--max-allowed-packet=1G`) is not applied; MariaDB's default applies.

Tests: `tests/static.sh`, `tests/smoke.sh`, `tests/persistence.sh` (local compose); `tests/railway-smoke.sh` and `--verify` (live HTTPS, redeploy).
