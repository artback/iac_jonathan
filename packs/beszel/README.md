# Beszel Nomad Pack

Deploys [Beszel](https://beszel.dev/) server monitoring on Nomad: the **hub** (web UI on
port 8090, history in the `beszel_vol` docker volume) and the **agent** (host metrics)
in one job. Replaces the previously hand-run `beszel` / `beszel-agent` docker containers,
reusing their volumes so history and the agent fingerprint are preserved.

## Data sources enabled

- CPU, memory, swap, load, root disk (nvme) — default agent metrics
- Per-container Docker stats — via read-only `docker.sock` mount
- Temperature sensors — `cpu_thermal` (primary), nvme, fan, voltages (host network + /sys)
- Extra filesystem: `/mnt/usbdrive` (698G USB drive), mounted read-only
- S.M.A.R.T. disk health — requires `agent_privileged = true` (default)
- Network interfaces — veth/docker/nomad bridges filtered out via `NICS`

## Variables

- `beszel_version` — pinned image tag for hub and agent. Never use `latest`
  (watchtower + `latest` is what OOM-broke grafana).
- `agent_token` / `agent_key` — WebSocket registration token and hub public key.
  **Secrets** — set them in `vars/beszel.hcl` (gitignored), not here.
- `agent_hub_url` — where the agent dials the hub (default `http://100.116.81.88:8090`).
- `extra_filesystems` — host mount points to monitor, mounted under `/extra-filesystems`.
- `primary_sensor`, `nics`, `hub_port`, `service_tags`, volume names — see `variables.hcl`.

## Deploy

```bash
nomad-pack run packs/beszel -f vars/beszel.hcl
```

## Upgrading

Bump `beszel_version` in `vars/beszel.hcl` (check the
[release notes](https://github.com/henrygd/beszel/releases)) and re-run the pack.
