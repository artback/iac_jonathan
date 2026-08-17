job "miniflux" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "miniflux-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = 8081
        to     = 8080
      }
    }

    # 1. AUTOMATION TASK: Create the DB and user if they don't exist
    task "db-init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        destination = "secrets/db_init.env"
        env         = true
        change_mode = "restart"
        data = <<EOH
          {{ with service "postgres" }}
          {{ with index . 0 }}
          DB_HOST="{{ .Address }}"
          DB_PORT="{{ .Port }}"
          {{ end }}
          {{ else }}
          DB_HOST="100.116.81.88"
          DB_PORT="5432"
          {{ end }}

          ROOT_DB_USER="[[ var "pg_root_user" . ]]"
          ROOT_DB_PASS="{{ with nomadVar "nomad/jobs/miniflux" }}{{ .db_root_password }}{{ end }}"
          NEW_DB_USER="[[ var "db_user" . ]]"
          NEW_DB_PASS="{{ with nomadVar "nomad/jobs/miniflux" }}{{ .db_password }}{{ end }}"
          NEW_DB_NAME="[[ var "db_name" . ]]"
        EOH
      }

      config {
        image = "postgres:16-alpine"
        args = [
          "sh", "-c",
          <<-EOT
          export PGPASSWORD=$ROOT_DB_PASS
          psql -h $DB_HOST -p $DB_PORT -U $ROOT_DB_USER -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '$NEW_DB_USER'" | grep -q 1 || \
          psql -h $DB_HOST -p $DB_PORT -U $ROOT_DB_USER -d postgres -c "CREATE USER $NEW_DB_USER WITH PASSWORD '$NEW_DB_PASS';"

          psql -h $DB_HOST -p $DB_PORT -U $ROOT_DB_USER -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$NEW_DB_NAME'" | grep -q 1 || \
          psql -h $DB_HOST -p $DB_PORT -U $ROOT_DB_USER -d postgres -c "CREATE DATABASE $NEW_DB_NAME OWNER $NEW_DB_USER;"

          # modern miniflux doesn't use hstore; migration v119 drops it and
          # fails if a superuser-owned extension exists — remove it up front
          psql -h $DB_HOST -p $DB_PORT -U $ROOT_DB_USER -d $NEW_DB_NAME -c "DROP EXTENSION IF EXISTS hstore;"
          EOT
        ]
      }
    }

    # 2. MAIN TASK: Miniflux
    task "miniflux" {
      driver = "docker"

      config {
        image = "miniflux/miniflux:[[ var "miniflux_version" . ]]"
        ports = ["http"]
      }

      template {
        destination = "secrets/miniflux.env"
        env         = true
        change_mode = "restart"
        data = <<EOH
          {{ with service "postgres" }}
          {{ with index . 0 }}
          DATABASE_URL="postgres://[[ var "db_user" . ]]:{{ with nomadVar "nomad/jobs/miniflux" }}{{ .db_password }}{{ end }}@{{ .Address }}:{{ .Port }}/[[ var "db_name" . ]]?sslmode=disable"
          {{ end }}
          {{ else }}
          DATABASE_URL="postgres://[[ var "db_user" . ]]:{{ with nomadVar "nomad/jobs/miniflux" }}{{ .db_password }}{{ end }}@100.116.81.88:5432/[[ var "db_name" . ]]?sslmode=disable"
          {{ end }}

          RUN_MIGRATIONS="1"
          CREATE_ADMIN="1"
          ADMIN_USERNAME="[[ var "admin_username" . ]]"
          ADMIN_PASSWORD="{{ with nomadVar "nomad/jobs/miniflux" }}{{ .admin_password }}{{ end }}"
          BASE_URL="[[ var "base_url" . ]]"
          TZ="Europe/Stockholm"
          # Retention. Miniflux's defaults (60d read / 180d unread) never fired
          # on this instance — 20 entries sat past the threshold with nothing
          # archived — so these are set explicitly rather than relied upon.
          CLEANUP_ARCHIVE_READ_DAYS="[[ var "cleanup_archive_read_days" . ]]"
          CLEANUP_ARCHIVE_UNREAD_DAYS="[[ var "cleanup_archive_unread_days" . ]]"
          CLEANUP_FREQUENCY_HOURS="[[ var "cleanup_frequency_hours" . ]]"
          # Prometheus already scrapes this cluster; without the collector a
          # feed can rot silently for weeks, which is the failure shape that
          # cost two days on the Consul side.
          METRICS_COLLECTOR="[[ var "metrics_collector" . ]]"
          METRICS_ALLOWED_NETWORKS="[[ var "metrics_allowed_networks" . ]]"
          # Poll busy feeds more often and quiet ones less, instead of one flat
          # interval for everything.
          POLLING_SCHEDULER="[[ var "polling_scheduler" . ]]"
          SCHEDULER_ENTRY_FREQUENCY_MIN_INTERVAL="[[ var "scheduler_min_interval" . ]]"
          SCHEDULER_ENTRY_FREQUENCY_MAX_INTERVAL="[[ var "scheduler_max_interval" . ]]"
          # Images are stripped per-feed by a remove(img) rewrite rule, so there
          # is nothing left to proxy.
          MEDIA_PROXY_MODE="[[ var "media_proxy_mode" . ]]"
        EOH
      }

      resources {
        cpu    = 200
        memory     = 128
        memory_max = 256
      }

      service {
        name = "miniflux"
        port = "http"
        tags = [[ var "service_tags" . | toStringList ]]

        check {
          name     = "alive"
          type     = "http"
          path     = "/healthcheck"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
  }
}
