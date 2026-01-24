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

job "mealie" {
  datacenters = var.datacenters
  type        = "service"

  group "mealie-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        to = 9000
      }
    }

    # 1. AUTOMATION TASK: Create the DB and User if they don't exist
    task "db-init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        destination = "local/db_init.env"
        env         = true
        change_mode = "restart"
        data = <<EOH
          DB_HOST="{{ range service "postgres" }}{{ .Address }}{{ end }}"
          DB_PORT="{{ range service "postgres" }}{{ .Port }}{{ end }}"
          # Fallback if service discovery fails
          {{ if eq (env "DB_HOST") "" }}
          DB_HOST="100.116.81.88"
          DB_PORT="5432"
          {{ end }}
          
          ROOT_DB_USER="${var.pg_root_user}"
          ROOT_DB_PASS="${var.db_postgresdb_root_password}"
          NEW_DB_USER="${var.db_postgresdb_user}"
          NEW_DB_PASS="${var.db_postgresdb_password}"
          NEW_DB_NAME="${var.db_postgresdb_database}"
        EOH
      }

      config {
        image = "postgres:16-alpine"
        args = [
          "sh", "-c",
          <<-EOT
          export PGPASSWORD=$ROOT_DB_PASS
          # Use values from template
          psql -h $DB_HOST -p $DB_PORT -U $ROOT_DB_USER -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '$NEW_DB_USER'" | grep -q 1 || \
          psql -h $DB_HOST -p $DB_PORT -U $ROOT_DB_USER -d postgres -c "CREATE USER $NEW_DB_USER WITH PASSWORD '$NEW_DB_PASS';"

          psql -h $DB_HOST -p $DB_PORT -U $ROOT_DB_USER -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$NEW_DB_NAME'" | grep -q 1 || \
          psql -h $DB_HOST -p $DB_PORT -U $ROOT_DB_USER -d postgres -c "CREATE DATABASE $NEW_DB_NAME OWNER $NEW_DB_USER;"
          EOT
        ]
      }
    }

    # 2. MAIN TASK: Mealie Application
    task "mealie" {
      driver = "docker"

      config {
        image = "ghcr.io/mealie-recipes/mealie:${var.mealie_version}"
        ports = ["http"]
      }

      template {
        destination = "local/mealie.env"
        env         = true
        change_mode = "restart"
        data = <<EOH
          # Mealie DB Connection Settings
          DB_ENGINE="postgres"
          POSTGRES_USER="${var.db_postgresdb_user}"
          POSTGRES_PASSWORD="${var.db_postgresdb_password}"
          POSTGRES_SCHEMA="${var.db_postgresdb_schema}"
          POSTGRES_DB="${var.db_postgresdb_database}"
          
          {{ with service "postgres" }}
          {{ with index . 0 }}
          POSTGRES_SERVER="{{ .Address }}"
          POSTGRES_PORT="{{ .Port }}"
          {{ end }}
          {{ else }}
          POSTGRES_SERVER="postgres.service.consul"
          POSTGRES_PORT="5432"
          {{ end }}

          # Required Mealie Settings
          BASE_URL="http://${var.domain}" 
          ALLOW_SIGNUP="true"
          TZ="UTC"
        EOH
      }

      resources {
        cpu    = 500
        memory = 1000
      }

      service {
        name = "mealie"
        port = "http"
        tags = var.service_tags

        check {
          name     = "alive"
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
