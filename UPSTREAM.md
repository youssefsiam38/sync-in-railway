# Upstream

- Project: https://github.com/Sync-in/server (AGPL-3.0-or-later)
- Image: `syncin/server` on Docker Hub (linux/amd64, linux/arm64)
- Database: `mariadb` on Docker Hub (official image)

## Pinned versions

| Component | Reference |
|---|---|
| Sync-in | `syncin/server:2.5.2@sha256:c6a618f955601722d033057f489380618310eda895f1eb1ea755570bee25fd40` |
| MariaDB | `mariadb:11.8@sha256:6422478cb8e159f080fb1d8ccf65101e26fe51385787fde7d16c3b165a331f15` |

No wrapper image is built. The template runs the upstream image as published.

## Refreshing a digest

```bash
docker buildx imagetools inspect syncin/server:2.5.2 | sed -n 's/^Digest: *//p' | head -1
docker buildx imagetools inspect mariadb:11.8       | sed -n 's/^Digest: *//p' | head -1
```

Pin the numbered tag, not `2`, `latest` or `11`. After a bump, update `compose.yaml`, `UPSTREAM.md`, and the spec, then run `tests/static.sh`, `tests/smoke.sh`, `tests/persistence.sh` and the live tests.

## Upstream settings the template relies on

- `scripts/docker-entrypoint.sh`: fixes `/app/data` ownership, drops to uid 8888 with `su-exec`.
- `scripts/docker-sync-in-server.sh`: waits for the database, runs migrations, creates the admin when `INIT_ADMIN` is set, writes `/app/.init` (in the container layer, so a new container re-runs the idempotent steps).
- `GET /healthz/ready`: public readiness endpoint, used as the Railway health check.
- Env overrides: `SYNCIN_` prefix, see `environment.dist.yaml`.
