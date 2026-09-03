# Homelab IaC

Nomad + Consul homelab running on a Raspberry Pi 5 (`kalmar` datacenter,
`europe` region), reachable over Tailscale. Services are deployed as
[nomad-pack](https://github.com/hashicorp/nomad-pack) packs and routed through
Fabio behind Tailscale Serve HTTPS.

```
https://raspberrypi.tailb9a8bb.ts.net/  (Tailscale Serve, real TLS cert)
        │
        ▼
Fabio :80  ── routes by Consul tag `urlprefix-/<name>`
        │
        ▼
Nomad jobs (Docker) ── registered in Consul with health checks
```

## Prerequisites (one-time, on your Mac)

```bash
brew install nomad nomad-pack go-task ansible
```

The Nomad/Consul APIs require mTLS. Client certs must live in
`~/.config/homelab/certs/` (`nomad-ca.pem`, `nomad-cli.pem`,
`nomad-cli-key.pem`, and the consul equivalents). The `Taskfile.yml` exports
the right `NOMAD_*` env vars automatically — verify with:

```bash
task status
```

## Deploy a new project (2 commands)

```bash
task new:service NAME=whoami IMAGE=traefik/whoami PORT=80
task deploy SERVICE=whoami
```

That's it — the service is live at
`https://raspberrypi.tailb9a8bb.ts.net/whoami`.

`new:service` scaffolds `vars/whoami.hcl` (see
[vars/whoami.example.hcl](vars/whoami.example.hcl)); edit it to add env vars,
volumes, resources, or a fixed host port, then re-run `task deploy`. The
`vars/` directory is gitignored because vars files may contain secrets — keep
a backup.

Services that need more than one container (sidecars, DB init hooks) get a
dedicated pack instead: copy `packs/mealie` as a template. `task deploy
SERVICE=<name>` automatically prefers `packs/<name>` over the generic pack.

Day-2 commands:

```bash
task plan SERVICE=whoami     # dry-run diff
task render SERVICE=whoami   # print the rendered job spec
task stop SERVICE=whoami     # stop and remove
task status                  # all jobs
```

> Gotcha: if a job was ever submitted with raw `nomad job run`, `nomad-pack`
> reports "Failed Job Conflict Validation". Fix:
> `nomad job stop -purge <name>` then `task deploy` again.

## Add a new node (3 steps)

1. Flash the OS (Raspberry Pi OS / Debian / Ubuntu), enable SSH, and create a
   Tailscale auth key at <https://login.tailscale.com/admin/settings/keys>
   (or join the node to Tailscale manually).
2. Add the node's IP under `[clients]` in `ansible/inventory.ini`
   (copy `ansible/inventory.ini.example` on first use).
3. Provision it:

   ```bash
   task node:provision HOST=<ip>
   ```

The playbook installs Tailscale, Docker, Consul, and Nomad (correct version
**and CPU architecture** — arm64 Pis and amd64 VMs both work), joins Consul to
the cluster at `100.116.81.88`, and starts a Nomad client that discovers the
servers through Consul. Re-running is safe and idempotent.

**The original Pi is protected:** its inventory entry carries
`*_skip_install=true` and `*_manage_config=false` because its on-disk config
was hand-tuned (mTLS, loopback-bound Consul) and predates these templates.
See [ansible/README.md](ansible/README.md) for details.

## Repository layout

| Path | Purpose |
| :--- | :--- |
| `Taskfile.yml` | All day-to-day commands (`task --list`). |
| `packs/generic/` | Deploy any single-container service from a vars file. |
| `packs/<name>/` | Dedicated packs (postgres, mealie, fabio, scriberr, webserver). |
| `vars/` | Per-service config (gitignored — may contain secrets). |
| `scripts/` | Scaffolding + service/pack resolution helpers. |
| `ansible/` | Node provisioning (Tailscale, Docker, Consul, Nomad). |
| `terraform/` | Optional AWS module for cloud nodes. |

## Troubleshooting

Run `task doctor` first — it checks the CLIs, certs, mTLS API, and the HTTPS
entry point. Then:

- **All service jobs `pending`, system jobs running, node `ready`** → Consul
  on the node is down. Nomad silently adds a
  `${attr.consul.version} >= 1.8.0` constraint to every service-registering
  job, and without a local Consul agent no node is eligible.
- **Consul crash-looping with "refusing to rejoin cluster ... server_rejoin_age_max"**
  → the node was offline >168h. Do **not** wipe the data dir; the config sets
  `server_rejoin_age_max = "87600h"` (on the Pi:
  `/etc/consul.d/zz-rejoin-age.hcl`).
- **Consul unit stuck `activating`, killed every 90s despite "agent running"
  in the logs** → Consul doesn't send systemd `READY=1` with TLS enabled. The
  Pi has a drop-in (`/etc/systemd/system/consul.service.d/override.conf`)
  setting `Type=exec`; the Ansible role's unit is already `Type=simple`.
- **`nomad` CLI gets EOF from the API** → client certs not found/presented.
  `task doctor` verifies the paths the Taskfile exports.
- **`nomad-pack` says "Failed Job Conflict Validation"** → job was once
  submitted with raw `nomad job run`; fix with `nomad job stop -purge <name>`
  then `task deploy`.

## Terraform (optional cloud nodes)

```bash
cd terraform/modules/nomad_cluster_aws
terraform init
terraform apply   # needs ssh_key_name in terraform.tfvars
```

Feed the output IPs into `ansible/inventory.ini` and provision them like any
other node.
