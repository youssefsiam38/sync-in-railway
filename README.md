# Sync-in on Railway

One-click Railway template for [Sync-in](https://github.com/Sync-in/server), a self-hosted platform for file storage, sync, sharing and collaboration. The template runs the upstream image unmodified, with a bundled MariaDB.

- **Upstream:** https://github.com/Sync-in/server (AGPL-3.0-or-later), image `syncin/server`
- **Services:** `server` (Sync-in, port 8080) and `db` (MariaDB 11.8)
- **Volumes:** `server` → `/app/data` (files), `db` → `/var/lib/mysql` (database)
- **Admin:** created from `INIT_ADMIN_LOGIN` / generated `INIT_ADMIN_PASSWORD` on the first start. There is no public sign-up.

## Deploy

Deploy the template from Railway. Copy the generated admin password from the `server` service variables, then sign in at your public domain with `admin` (or the login you set in `INIT_ADMIN_LOGIN`).

## Configuration

| Variable | Service | Notes |
|---|---|---|
| `INIT_ADMIN_LOGIN` | server | Administrator login, created on first start |
| `INIT_ADMIN_PASSWORD` | server | Generated. Change it in Sync-in later |
| `SYNCIN_SERVER_PUBLICURL` | server | `https://${{RAILWAY_PUBLIC_DOMAIN}}`. Change it if you add a custom domain |
| `SYNCIN_MYSQL_URL` | server | Built from `db` over Railway's private network |
| `SYNCIN_AUTH_*` | server | Generated secrets. Keep them stable |
| `MARIADB_ROOT_PASSWORD` | db | Generated. The app connects as root, as upstream does |

Optional mail (`SYNCIN_MAIL_*`) and auth provider (`SYNCIN_AUTH_PROVIDER`) variables are listed in the template. Upstream documents the rest under `environment.dist.yaml`. Any upstream setting can be given as an env var with the `SYNCIN_` prefix and the path joined by `_`, e.g. `SYNCIN_APPLICATIONS_FILES_DATAPATH`.

## Design decisions

- **Stock image, no wrapper.** The upstream entrypoint already drops privileges, fixes volume ownership and runs migrations and the admin bootstrap. Nothing needed patching.
- **Admin from env.** No first-run page is open to the internet.
- **Root database user.** Upstream runs `SET GLOBAL event_scheduler` at boot, which needs SUPER. A restricted user falls back to an internal scheduler and logs an error. The root password is generated and used only on the private network.
- **Full-text tuning.** Upstream's compose sets `--innodb_ft_cache_size` and `--max-allowed-packet=1G` for document indexing. The Railway template does not pass them, because a start-command override would bypass the MariaDB entrypoint. MariaDB's default `max_allowed_packet` (16M) applies. See the known limits below.

## Testing

Local (Docker Compose, same images by digest):

```bash
tests/static.sh        # syntax, shellcheck, compose shape, pins, secret hygiene
tests/smoke.sh         # boot, admin bootstrap, auth gates, file flows, restart
tests/persistence.sh   # files and accounts survive a full container recreate
```

Live (against a deployed template, over HTTPS):

```bash
APP_URL=https://<domain> SYNC_IN_PASSWORD_FILE=<mode-600 file with the admin password> STATE_FILE=<file> tests/railway-smoke.sh
APP_URL=https://<domain> SYNC_IN_PASSWORD_FILE=<same file> STATE_FILE=<same file> tests/railway-smoke.sh --verify   # after a redeploy
```

The live run covers the HTTPS edge, anonymous refusal, wrong and unknown logins, admin sign-in, folder create, upload, listing, byte-exact download and delete. The `--verify` run checks that a file uploaded before a redeploy of both services is still there.

## Known limits

- Not tested: full-text indexing of very large documents under MariaDB's default 16M `max_allowed_packet`. Upstream's compose raises it to 1G.
- The `server` service is single-instance with one worker (upstream default). Scale-out needs Redis and upstream's cluster guidance.
- Desktop/CLI release hosting, Collabora/OnlyOffice/draw.io editors and nginx are not part of this template.

## Licence

Sync-in itself is AGPL-3.0-or-later; see [LICENSE](LICENSE). Sync-in® is a registered trademark, see the upstream [trademark policy](https://sync-in.com/trademark). This is a community template, not affiliated with the Sync-in project.
