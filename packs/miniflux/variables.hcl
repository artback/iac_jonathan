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
  description = "The tags for the miniflux service."
  type        = list(string)
  default     = ["miniflux"]
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
