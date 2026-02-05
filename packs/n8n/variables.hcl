variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["dc1"]
}

variable "count" {
  description = "The number of instances to run."
  type        = number
  default     = 1
}

variable "port" {
  description = "The port for n8n."
  type        = number
  default     = 5678
}

variable "image" {
  description = "The Docker image to use."
  type        = string
  default     = "docker.n8n.io/n8nio/n8n"
}

variable "cpu" {
  description = "The CPU resources to allocate."
  type        = number
  default     = 500 # n8n can be resource-intensive
}

variable "memory" {
  description = "The memory resources to allocate."
  type        = number
  default     = 1024 # n8n can be resource-intensive
}

variable "volume_id" {
  description = "The name of the docker volume."
  type        = string
  default     = "n8n_data"
}

variable "n8n_tags" {
  description = "The tags for the n8n service."
  type        = list(string)
  default     = ["urlprefix-/n8n"]
}

variable "generic_timezone" {
  description = "The generic timezone for n8n."
  type        = string
  default     = "Europe/Berlin"
}

variable "tz" {
  description = "The timezone for n8n."
  type        = string
  default     = "Europe/Berlin"
}

variable "n8n_enforce_settings_file_permissions" {
  description = "Enforce settings file permissions."
  type        = bool
  default     = true
}

variable "n8n_runners_enabled" {
  description = "Enable n8n runners."
  type        = bool
  default     = true
}

variable "db_type" {
  description = "The type of database to use."
  type        = string
  default     = "postgresdb"
}

variable "db_postgresdb_database" {
  description = "The PostgreSQL database name."
  type        = string
}

variable "db_postgresdb_user" {
  description = "The PostgreSQL user."
  type        = string
}

variable "db_postgresdb_schema" {
  description = "The PostgreSQL schema."
  type        = string
}

variable "db_postgresdb_password" {
  description = "The PostgreSQL password."
  type        = string
}

variable "db_postgresdb_timeout" {
  description = "The PostgreSQL database timeout."
  type        = number
  default  = 30000
}
