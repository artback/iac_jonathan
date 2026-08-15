# Generic Pack

Deploys any single-container Docker service to the cluster. For most new
projects you never need a new pack — just a vars file.

## Quick start

```bash
task new:service NAME=whoami IMAGE=traefik/whoami PORT=80
task deploy SERVICE=whoami
```

This scaffolds `vars/whoami.hcl` and deploys it. The service becomes reachable
at `https://raspberrypi.tailb9a8bb.ts.net/whoami` via Fabio.

## Vars file reference

```hcl
job_name = "whoami"                 # required
image    = "traefik/whoami:latest"  # required
port     = 80                       # required — container port

url_prefix        = "/whoami"       # Fabio route ("" = not routed)
strip_prefix      = true            # strip path before proxying
health_check_path = "/"             # "" = TCP check instead of HTTP
count             = 1
cpu               = 200             # MHz
memory            = 256             # MB
static_port       = 0               # fixed host port for apps that need one

env_vars = {
  TZ = "Europe/Stockholm"
}
args    = []                        # container args
volumes = ["/opt/whoami:/data"]     # host:container — host path must exist

extra_tags = []                     # extra Consul tags
```

When you outgrow this pack (sidecars, prestart hooks, templates), copy an
existing dedicated pack like `packs/mealie` as a starting point.
