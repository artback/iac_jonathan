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

job "n8n" {
  datacenters = var.datacenters
  type        = "service"

  group "n8n" {
    count = var.count


    restart {
      attempts = 10        # Try more times locally
      interval = "30m"
      delay    = "15s"
      mode     = "delay"   # "delay" keeps trying forever after the interval resets
    }

    reschedule {
      unlimited = true
      delay     = "30s"
      delay_function = "exponential"
    }

    network {
      mode = "bridge"
      port "http" {
        static = var.port
      }
    }

    task "n8n" {
      driver = "docker"

      service {
        name = "n8n"
        tags = var.n8n_tags
        port = "http"
        provider = "consul"
      }


      config {
        image = var.image
        ports = ["http"]
        mounts = [
          {
            type     = "volume"
            source   = var.volume_id    # Uses "n8n_data" (Name, not path)
            target   = "/home/node/.n8n"
            readonly = false
          },
          {

            type     = "bind"
            source   =  "/home/dwight/Job applications/"    # Uses "n8n_data" (Name, not path)
            target   = "/home/node/.n8n-files/"
            readonly = false
          }
        ]
      }
      resources {
        cpu    = var.cpu
        memory = var.memory # Now it uses the 1024MB from above
      }

      template {
        destination = "local/n8n.env"
        env         = true
        change_mode = "noop"

        data = <<EOH
            GENERIC_TIMEZONE="${var.generic_timezone}"
            TZ="${var.tz}"
            N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=${var.n8n_enforce_settings_file_permissions}
            N8N_RUNNERS_ENABLED=${var.n8n_runners_enabled}
            N8N_SECURE_COOKIE=false

            DB_TYPE="${var.db_type}"
            DB_POSTGRESDB_DATABASE="${var.db_postgresdb_database}"
            DB_POSTGRESDB_SCHEMA="${var.db_postgresdb_schema}"
            DB_POSTGRESDB_USER="${var.db_postgresdb_user}"
            DB_POSTGRESDB_PASSWORD="${var.db_postgresdb_password}"
            DB_POSTGRESDB_CONNECTION_TIMEOUT=${var.db_postgresdb_timeout}
            {{ with service "postgres" }}
            {{ with index . 0 }}
            DB_POSTGRESDB_HOST="{{ .Address }}"
            DB_POSTGRESDB_PORT="{{ .Port }}"
            {{ end }}
            {{ else }}
            # FALLBACK: Consul couldn't find Postgres, using Tailscale IP
            DB_POSTGRESDB_HOST="100.116.81.88"
            DB_POSTGRESDB_PORT="5432"
            {{ end }}
        EOH
      }
    }
  }
}
