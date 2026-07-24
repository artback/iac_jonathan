# Backup Nomad Pack

Nightly (03:00 UTC) backup job, replacing the old dump-only `postgres-backup` job.
Each run produces, with 7-day day-of-week rotation (`-1`..`-7`):

- `postgres/pg-dumpall-N.sql.gz` — full `pg_dumpall` (n8n, mealie, everything)
- `app-state/app-state-N.tar.gz` — docker-volume state the DB dump can't restore:
  - `n8n/` — **`config` holds the n8n encryption key**; without it a restored DB
    has undecryptable credentials. Also `binaryData/`.
  - `mealie/` — recipe images (`/app/data`, named volume `mealie_data`)
  - `beszel/` — monitoring history (live sqlite copy, crash-consistent)

Both artifacts are written to **two disks**:

- `/home/dwight/backups` (NVMe — same disk as the data, fast local copy)
- `/mnt/usbdrive/backups` (USB drive — survives an NVMe failure)

Off-device/offsite sync is NOT handled here (candidate next step: restic/rclone).

## Variables

- `pg_password` — postgres superuser password. **Secret** — set in gitignored
  `vars/backup.hcl`.
- `app_state_paths` — map of `name = host path` included in the app-state tarball.
  Add new stateful services here when you add them to the cluster.
- `cron`, `local_backup_dir`, `usb_backup_dir`, `pg_user` — see `variables.hcl`.

## Deploy / run now

```bash
nomad-pack run packs/backup -f vars/backup.hcl
nomad job periodic force backup
```

## Restore notes

- Postgres: `zcat pg-dumpall-N.sql.gz | psql -h <host> -U postgres`
- n8n: restore DB, then untar `n8n/` back into the `n8n_data` volume **before**
  starting n8n (the `config` file must match the DB's encrypted credentials).
- Mealie: restore DB + untar `mealie/` into the `mealie_data` volume.
