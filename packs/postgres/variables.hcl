variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["dc1"]
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
