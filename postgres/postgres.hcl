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

# This job file defines a PostgreSQL service in Nomad.
job "postgres" {
  # Specifies the datacenters where the job can run.
  datacenters = var.datacenters
  type        = "service"

  # A group defines a set of tasks that should be co-located on the same client.
  group "postgres-group" {
    count = 1

    network {
      mode = "bridge"
      port "db" {
        static = var.db_port
      }
    }
    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:${var.pg_version}-alpine"
        ports = ["db"]
        volumes = [
          "${var.docker_volume_name}:/var/lib/postgresql",
        ]
      }

      env {
        POSTGRES_USER     = var.pg_user
        POSTGRES_PASSWORD = var.pg_password # Best practice is to use Nomad Secrets/Vault for this
        POSTGRES_DB       = var.pg_db_name
      }

      service {
        name = "postgres"
        tags = [
          "postgres"
        ]
        provider = "consul"
        port = "db"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
