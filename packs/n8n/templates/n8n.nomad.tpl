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
