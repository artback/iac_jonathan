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
  default     = 512 # n8n can be resource-intensive
}

variable "n8n_tags" {
  description = "The tags for the n8n service."
  type        = list(string)
  default     = ["urlprefix-/n8n"]
}

variable "volume_id" {
  description = "The ID of the host volume to use for data persistence."
  type        = string
  default     = "n8n_data"
}

variable "host_volume_name" {
  description = "The name of the host volume on the Nomad client."
  type        = string
  default     = "/opt/n8n-data"
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

variable "db_postgresdb_host" {
  description = "The PostgreSQL host."
  type        = string
}

variable "db_postgresdb_port" {
  description = "The PostgreSQL port."
  type        = number
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

job "n8n" {
  datacenters = var.datacenters
  type        = "service"

  group "n8n" {
    count = var.count
    
    volume "${var.volume_id}" {
      type      = "host"
      source    = var.host_volume_name
      read_only = false
    }

    network {
      port "http" {
        static = var.port
      }
    }

    service {
      name = "n8n"
      tags = var.n8n_tags
      port = "http"
      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "n8n" {
      driver = "docker"
      config {
        image = var.image
        ports = ["http"]
      }
      env {
        GENERIC_TIMEZONE                        = var.generic_timezone
        TZ                                      = var.tz
        N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = var.n8n_enforce_settings_file_permissions
        N8N_RUNNERS_ENABLED                     = var.n8n_runners_enabled
        DB_TYPE                                 = var.db_type
        DB_POSTGRESDB_DATABASE                  = var.db_postgresdb_database
        DB_POSTGRESDB_HOST                      = var.db_postgresdb_host
        DB_POSTGRESDB_PORT                      = var.db_postgresdb_port
        DB_POSTGRESDB_USER                      = var.db_postgresdb_user
        DB_POSTGRESDB_SCHEMA                    = var.db_postgresdb_schema
        DB_POSTGRESDB_PASSWORD                  = var.db_postgresdb_password
      }
      resources {
        cpu    = var.cpu
        memory = var.memory
      }
      volume_mount {
        volume      = var.volume_id
        destination = "/home/node/.n8n"
        read_only   = false
      }
    }
  }
}
