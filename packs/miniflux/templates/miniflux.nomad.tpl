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
          ROOT_DB_PASS="[[ var "db_root_password" . ]]"
          NEW_DB_USER="[[ var "db_user" . ]]"
          NEW_DB_PASS="[[ var "db_password" . ]]"
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
          DATABASE_URL="postgres://[[ var "db_user" . ]]:[[ var "db_password" . ]]@{{ .Address }}:{{ .Port }}/[[ var "db_name" . ]]?sslmode=disable"
          {{ end }}
          {{ else }}
          DATABASE_URL="postgres://[[ var "db_user" . ]]:[[ var "db_password" . ]]@100.116.81.88:5432/[[ var "db_name" . ]]?sslmode=disable"
          {{ end }}

          RUN_MIGRATIONS="1"
          CREATE_ADMIN="1"
          ADMIN_USERNAME="[[ var "admin_username" . ]]"
          ADMIN_PASSWORD="[[ var "admin_password" . ]]"
          BASE_URL="[[ var "base_url" . ]]"
          TZ="Europe/Stockholm"
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
