# Deploy and Host Sync-in on Railway

Sync-in is a self-hosted platform for file storage, sync, sharing and team collaboration. This template deploys the upstream Sync-in server with a bundled MariaDB database. The administrator is created from variables on the first start, and public sign-up is closed. Community-maintained template, not affiliated with the Sync-in project, and no logo is used.

## About Hosting Sync-in

Sync-in runs as a single service that stores your files on a Railway volume at `/app/data`. Accounts, shares and the file index live in MariaDB on a second volume. Both services redeploy without losing data. The administrator password is generated and shown in the service variables; sign in at your public domain and change it in the app.

## Common Use Cases

- Private file storage and sync for a small team, on your own infrastructure
- Sharing files with links that have passwords, expiry dates and access limits
- WebDAV access from file explorers, network drives and mobile apps
- Full-text search across documents, with indexing run by the server

## Dependencies for Sync-in Hosting

- MariaDB 11.8, deployed in the same template on Railway's private network
- Optional: an SMTP server for notification and password e-mail; an OIDC or LDAP provider for single sign-on

### Deployment Dependencies

- Sync-in: https://github.com/Sync-in/server (AGPL-3.0-or-later)
- Template repository and tests: https://github.com/youssefsiam38/sync-in-railway

### Implementation Details

The template runs the upstream `syncin/server` image unmodified, pinned by tag and digest, with the upstream `mariadb` image pinned the same way. The server listens on port 8080 with a public domain and the health check at `/healthz/ready`. Files are on a volume at `/app/data`. The database is on a volume at `/var/lib/mysql`, reached over the private network. The administrator is created from `INIT_ADMIN_LOGIN` and a generated `INIT_ADMIN_PASSWORD`. Secrets for token signing and at-rest encryption are generated. Tested in CI and on a live deployment: sign-in, folder creation, upload, download, deletion, and data surviving a redeploy of both services.

## Why Deploy Sync-in on Railway?

Railway runs the server and database as separate services with managed volumes, HTTPS on your domain, and redeploys from the template. You keep the data on infrastructure you control, without running a reverse proxy or a database by hand.

Deploy in a few clicks, change the admin login and domain in the variables, and start uploading. Add mail or single sign-on later from the same service's variables.
