variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

# The Tailscale address of the client. The groups run in separate network
# namespaces, so they reach each other through this address and the static
# ports below rather than over localhost — the same arrangement fabio uses.
variable "service_ip" {
  description = "Routable host IP the services advertise and address each other by."
  type        = string
  default     = "100.116.81.88"
}

# ---------------------------------------------------------------------------
# Application image
# ---------------------------------------------------------------------------

variable "image" {
  description = "The museum image. Must be built for linux/arm64 — the client is a Raspberry Pi."
  type        = string
  default     = "ghcr.io/artback/museum:latest"
}

variable "api_port" {
  description = "Static host port for the HTTP API. 8090 is taken by beszel."
  type        = number
  default     = 8091
}

variable "service_tags" {
  description = "Consul tags for the API service, used by fabio for routing."
  type        = list(string)
  # The app's own paths, routed unstripped.
  #
  # A single "urlprefix-/museum strip=/museum" would be the obvious choice and
  # does not work: the map page requests /v1/... and /map/vendor/... as
  # absolute paths, so everything it loads would miss the prefix and fall
  # through to the dashboard on "/". Routing the real paths instead means
  # http://100.116.81.88/map works and so does every request it makes.
  #
  # Both are longer than the dashboard's "urlprefix-/", and fabio matches the
  # longest prefix, so these win without the dashboard needing to change.
  # museum.localhost is kept for anyone addressing it by host.
  default = [
    "urlprefix-/map",
    "urlprefix-/v1",
    "urlprefix-museum.localhost/",
  ]
}

variable "nominatim_user_agent" {
  description = "Sent to Nominatim, whose usage policy rejects generic agents."
  type        = string
  default     = "museum-pipeline/1.0 (homelab; https://github.com/artback/museumscraper)"
}

# ---------------------------------------------------------------------------
# Tailscale
#
# Joins the tailnet as a device in its own right, so the catalogue answers to
# https://museum.<tailnet>.ts.net rather than to the Pi's hostname and a path.
# The sidecar shares the API group's network namespace, so it proxies to the
# API over loopback and nothing extra is published on the host.
# ---------------------------------------------------------------------------

variable "enable_tailscale" {
  description = "Join the tailnet as its own device. Requires tailscale_authkey."
  type        = bool
  default     = false
}

variable "tailscale_image" {
  description = "Tailscale image. Multi-arch, so it runs on the Pi."
  type        = string
  default     = "tailscale/tailscale:stable"
}

variable "tailscale_hostname" {
  description = "The device name, and therefore the first label of the MagicDNS name."
  type        = string
  default     = "museum"
}

variable "tailnet_suffix" {
  description = <<-EOD
    The tailnet's MagicDNS suffix, from `tailscale status --json`.

    Written out in full rather than read from the container's TS_CERT_DOMAIN,
    because that placeholder would have to survive HCL interpolation — and
    $${} escaping through nomad-pack is the documented trap in this repository.
  EOD
  type        = string
  default     = "tailb9a8bb.ts.net"
}

variable "tailscale_authkey" {
  description = <<-EOD
    A reusable, non-ephemeral auth key (secret — set in the vars file).

    Reusable because the task re-authenticates whenever it starts without
    saved state; non-ephemeral so the device is not removed from the tailnet
    the moment the allocation stops. Generate at
    https://login.tailscale.com/admin/settings/keys
  EOD
  type        = string
  default     = ""
}

variable "tailscale_state_volume" {
  description = <<-EOD
    Volume holding the node's identity.

    Without it every replaced allocation registers a *new* device — museum-1,
    museum-2 — and the name you wanted drifts away while the auth key is spent
    on each one.
  EOD
  type        = string
  default     = "museum-tailscale-state"
}

# ---------------------------------------------------------------------------
# PostgreSQL + PostGIS
#
# A second Postgres rather than the shared "postgres" job: the catalogue needs
# the postgis and pg_trgm extensions for its radius and similarity queries, and
# the shared instance runs postgres:18-alpine, which has neither.
# ---------------------------------------------------------------------------

variable "pg_image" {
  description = <<-EOD
    PostGIS image. Not postgis/postgis — that repository publishes amd64 only
    and will not run on the Pi. imresamu/postgis is the multi-arch build of the
    same Dockerfile, maintained by a docker-postgis maintainer.
  EOD
  type        = string
  default     = "imresamu/postgis:16-3.4"
}

variable "pg_port" {
  description = "Static host port for the catalogue database. 5432 is the shared postgres."
  type        = number
  default     = 55432
}

variable "pg_user" {
  description = "Owner of the catalogue database. Also the superuser, which CREATE EXTENSION postgis requires."
  type        = string
  default     = "museum"
}

variable "pg_password" {
  description = "Password for the catalogue database (secret — set in the vars file)."
  type        = string
}

variable "pg_db_name" {
  description = "The catalogue database name."
  type        = string
  default     = "museum"
}

variable "pg_volume" {
  description = "Docker volume holding the catalogue database."
  type        = string
  default     = "museum-postgres-data"
}

# ---------------------------------------------------------------------------
# Object storage
# ---------------------------------------------------------------------------

variable "minio_image" {
  description = "MinIO image."
  type        = string
  default     = "quay.io/minio/minio:latest"
}

variable "mc_image" {
  description = "MinIO client image, used to create the bucket and its event rule."
  type        = string
  default     = "minio/mc:latest"
}

variable "minio_port" {
  description = <<-EOD
    Static host port for the MinIO S3 API.

    9000 is mealie and 9100 is node-exporter — the latter does not appear in
    this repository's packs, only on the cluster, so it is invisible to a
    grep of the job files. Taking it put node-exporter into a restart loop
    and stopped Prometheus seeing any host metrics.
  EOD
  type        = number
  default     = 9110
}

variable "minio_console_port" {
  description = "Static host port for the MinIO console."
  type        = number
  default     = 9111
}

variable "minio_root_user" {
  description = "MinIO root user."
  type        = string
  default     = "minioadmin"
}

variable "minio_root_password" {
  description = "MinIO root password (secret — set in the vars file)."
  type        = string
}

variable "minio_volume" {
  description = "Docker volume holding the raw and enriched source records."
  type        = string
  default     = "museum-minio-data"
}

variable "bucket_name" {
  description = "Bucket holding both raw_data/ and enriched_data/."
  type        = string
  default     = "museum"
}

# ---------------------------------------------------------------------------
# Kafka
# ---------------------------------------------------------------------------

variable "kafka_image" {
  description = "Kafka image, running in KRaft mode as a single broker."
  type        = string
  default     = "apache/kafka:3.9.1"
}

variable "kafka_port" {
  description = "Static host port for the Kafka external listener."
  type        = number
  default     = 29092
}

variable "kafka_topic" {
  description = "Topic carrying MinIO ObjectCreated events to the enricher."
  type        = string
  default     = "raw.museum.ingestion.events.v1"
}

variable "kafka_group_id" {
  description = "Consumer group for the enricher."
  type        = string
  default     = "address_enricher"
}

variable "kafka_volume" {
  description = "Docker volume holding the Kafka log directory."
  type        = string
  default     = "museum-kafka-data"
}

variable "kafka_heap" {
  description = "JVM heap for the broker. Deliberately small: this is an 8 GB Pi shared with sixteen other allocations."
  type        = string
  default     = "-Xmx512m -Xms256m"
}

# ---------------------------------------------------------------------------
# Pipeline
#
# The enricher, and the scheduled crawl and refresh, are what make the Pi able
# to maintain the catalogue rather than only serve a copy of it. They are the
# expensive half of the stack, so they can be turned off independently.
# ---------------------------------------------------------------------------

variable "enable_pipeline" {
  description = <<-EOD
    Run MinIO, Kafka and the enricher. With this false only PostGIS and the API
    are deployed: the catalogue is still served in full, but it can no longer be
    crawled or enriched on the Pi, and would be updated by restoring a dump
    taken elsewhere. Saves roughly 1.8 GiB of reservation.
  EOD
  type        = bool
  default     = true
}

variable "seed_mode" {
  description = <<-EOD
    Deploy for loading existing data in, rather than for running.

    The enricher does not check whether a record has already been enriched: it
    geocodes every museum an event names, and then makes a second Nominatim call
    for the place details. Mirroring the 345,000 existing objects into a bucket
    that has the notification rule attached would therefore queue roughly 690,000
    requests against a geocoder that allows one per second — about eight days of
    traffic, against a usage policy that forbids bulk geocoding outright.

    With this true the bucket notification is not attached and the enricher runs
    zero instances, so the seed lands quietly. Set it back to false and redeploy
    once the data is in; from then on only newly crawled records raise events.
  EOD
  type        = bool
  default     = false
}

variable "refresh_cron" {
  description = "When to rescrape exhibition listings (UTC)."
  type        = string
  default     = "0 4 * * *"
}

variable "refresh_max_museums" {
  description = "Cap on museums scraped per refresh run (0 for no limit)."
  type        = number
  default     = 500
}

variable "refresh_concurrency" {
  description = "How many museum sites to read at once. Below the binary's default of 8 — the Pi shares one uplink with sixteen other allocations."
  type        = number
  default     = 4
}

variable "crawl_cron" {
  description = "When to recrawl the sources and reindex (UTC). Weekly — a full crawl is hours of rate-limited work."
  type        = string
  default     = "0 1 * * 0"
}

variable "enable_crawl" {
  description = "Register the weekly crawl job. Off by default: it saturates the Pi for hours."
  type        = bool
  default     = false
}

variable "crawl_sources" {
  description = "Which sources the crawl reads. Excludes osm by default, as the binary does — Overpass is the slowest and the least reliable of the four."
  type        = string
  default     = "wikidata,category,lists"
}

# ---------------------------------------------------------------------------
# Backups
#
# The shared "backup" job runs pg_dumpall against the shared postgres only, so
# it does not see this database. These values mirror its two-copy convention:
# once to the NVMe, once to the USB drive.
# ---------------------------------------------------------------------------

variable "backup_cron" {
  description = "When to dump the catalogue (UTC)."
  type        = string
  default     = "30 3 * * *"
}

variable "local_backup_dir" {
  description = "Backup destination on the NVMe (same disk as the data — first copy)."
  type        = string
  default     = "/home/dwight/backups"
}

variable "usb_backup_dir" {
  description = "Backup destination on the USB drive (separate physical disk — second copy)."
  type        = string
  default     = "/mnt/usbdrive/backups"
}

variable "backup_keep" {
  description = "How many catalogue dumps to keep in each destination."
  type        = number
  default     = 7
}
