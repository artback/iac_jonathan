variable "datacenters" {
  description = "The datacenters where the job should run."
  type = list(string)
  default = ["dc1"]
}


variable "host_volume_name" {
  description = "The name of the host volume on the Nomad client."
  type        = string
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

# This job file defines a PostgreSQL service in Nomad.
job "postgres" {
  # Specifies the datacenters where the job can run.
  datacenters = var.datacenters
  type = "service"

  # A group defines a set of tasks that should be co-located on the same client.
  group postgres-group {
    count = 1

    volume pgdata {
      type      = "host"
      source    = "${var.host_volume_name}"
      read_only = false
    }

    network {
      mode = "bridge"
      port "db" {}
    }
      task "postgres" {
        driver = "docker"

        config {
          image = "postgres:${var.pg_version}-alpine"
          ports = ["db"]
        }

        env {
          POSTGRES_PASSWORD = "${var.pg_password}" # Best practice is to use Nomad Secrets/Vault for this
          POSTGRES_DB = "${var.pg_db_name}"
        }

        # Mounts the host volume into the container.
        volume_mount {
          volume      = "pgdata"
          destination = "/var/lib/postgresql/data"
          read_only   = false
        }
        service {
          name = "postgres"
          tags = [
            "postgres"
          ]
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