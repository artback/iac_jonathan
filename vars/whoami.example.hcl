# Example service definition for the generic pack.
# Copy to vars/<name>.hcl (or run: task new:service NAME=... IMAGE=... PORT=...)
# and deploy with: task deploy SERVICE=<name>
#
# Full option reference: packs/generic/README.md

job_name = "whoami"
image    = "traefik/whoami:latest"
port     = 80

# Route: https://raspberrypi.tailb9a8bb.ts.net/whoami
url_prefix        = "/whoami"
strip_prefix      = true
health_check_path = "/"

count  = 1
cpu    = 200
memory = 128

env_vars = {
  TZ = "Europe/Stockholm"
}
