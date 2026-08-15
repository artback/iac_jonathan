variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "backup_dir" {
  description = "Host directory the nightly pg_dumpall lands in (7-day rotation). Must exist on the node."
  type        = string
  default     = "/home/dwight/backups/postgres"
}

variable "docker_volume_name" {
  description = "The name of the Docker volume for data persistence."
  type        = string
  default     = "postgres-data"
}

variable "pg_version" {
  description = "The version of PostgreSQL to use."
  type        = string
}

variable "pg_password" {
  description = "The password for the PostgreSQL database."
  type        = string
}

variable "pg_db_name" {
  description = "The name of the PostgreSQL database."
  type        = string
}

variable "db_port" {
  description = "The port to expose for the database."
  type        = number
  default     = 5432
}

variable "pg_user" {
  description = "The PostgreSQL user."
  type        = string
  default     = "postgres"
}
