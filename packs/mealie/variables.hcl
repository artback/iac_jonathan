variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "domain" {
  description = "The root domain for the application (e.g., example.com)."
  type        = string
  default     = "localhost"
}

variable "mealie_version" {
  description = "The version of Mealie to run."
  type        = string
  default     = "latest"
}

variable "db_postgresdb_schema" {
  description = "The PostgreSQL schema."
  type        = string
  default     = "public"
}

variable "pg_root_user" {
  description = "The root user for Postgres (to create the mealie db/user)."
  type        = string
  default     = "postgres"
}

variable "db_postgresdb_root_password" {
  description = "The root password for Postgres."
  type        = string
}

variable "db_postgresdb_user" {
  description = "The database user for Mealie."
  type        = string
  default     = "mealie"
}

variable "db_postgresdb_password" {
  description = "The database password for Mealie."
  type        = string
}

variable "db_postgresdb_database" {
  description = "The database name for Mealie."
  type        = string
  default     = "mealie"
}

variable "service_tags" {
  description = "The tags for the mealie service."
  type        = list(string)
  default     = ["urlprefix-mealie.localhost/"]
}
