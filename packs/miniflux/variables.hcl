variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "miniflux_version" {
  description = "The Miniflux version to run. Pin this — do not use latest."
  type        = string
  default     = "2.3.3"
}

variable "base_url" {
  description = "Public base URL of the instance."
  type        = string
  default     = "http://100.116.81.88:8081/"
}

variable "admin_username" {
  description = "Initial admin username (created on first run)."
  type        = string
  default     = "jonathan"
}

variable "pg_root_user" {
  description = "The root user for Postgres (to create the miniflux db/user)."
  type        = string
  default     = "postgres"
}

variable "db_user" {
  description = "The database user for Miniflux."
  type        = string
  default     = "miniflux"
}

variable "db_name" {
  description = "The database name for Miniflux."
  type        = string
  default     = "miniflux"
}

variable "service_tags" {
  description = "Consul tags. \"metrics\" opts this service into the prometheus pack's consul-services scrape job, which keeps only services carrying that tag."
  type        = list(string)
  default     = ["miniflux", "metrics"]
}

variable "cleanup_archive_read_days" {
  description = "Archive read entries older than this many days."
  type        = number
  default     = 10
}

variable "cleanup_archive_unread_days" {
  description = "Archive unread entries older than this many days. Checked against the backlog before changing: most unread items here are under a month old."
  type        = number
  default     = 30
}

variable "cleanup_frequency_hours" {
  description = "How often the cleanup sweep runs."
  type        = number
  default     = 24
}

variable "metrics_collector" {
  description = "Expose Prometheus metrics at /metrics."
  type        = string
  default     = "1"
}

variable "metrics_allowed_networks" {
  description = "CIDRs permitted to scrape /metrics: the Nomad bridge (where Prometheus runs) and the tailnet. Not the LAN."
  type        = string
  default     = "127.0.0.1/32,172.26.64.0/20,100.64.0.0/10"
}

variable "polling_scheduler" {
  description = "entry_frequency adapts the poll interval to how often a feed actually publishes."
  type        = string
  default     = "entry_frequency"
}

variable "scheduler_min_interval" {
  description = "Floor for adaptive polling, minutes."
  type        = number
  default     = 15
}

variable "scheduler_max_interval" {
  description = "Ceiling for adaptive polling, minutes."
  type        = number
  default     = 1440
}

variable "media_proxy_mode" {
  description = "none/http-only/all. Images are stripped at fetch time, so nothing needs proxying."
  type        = string
  default     = "none"
}

