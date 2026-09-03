[[ if var "enable_crawl" . ]]
# Rebuilds the catalogue from Wikidata, Wikipedia and OpenStreetMap, then loads
# the result into the database.
#
# Hours of rate-limited work, weekly, on a Pi shared with sixteen other
# allocations — so it runs at 01:00 and never overlaps itself.
#
# It does not flood the enricher, despite writing the whole catalogue: the
# object store skips keys that are already present, so a rerun raises events
# only for museums that are actually new. The first load is the exception, and
# that is what seed_mode is for.
job "museum-crawl" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "batch"

  periodic {
    crons            = ["[[ var "crawl_cron" . ]]"]
    time_zone        = "UTC"
    prohibit_overlap = true
  }

  group "crawl" {
    count = 1

    network {
      mode = "bridge"
    }

    # crawl writes the raw records; reindex then loads them into the database,
    # preferring the enriched copy of a museum over the raw one. Running
    # reindex as a poststop task is what keeps the two in one unit — a crawl
    # whose reindex never ran leaves the API serving the previous catalogue.
    task "crawl" {
      driver = "docker"

      config {
        image = "[[ var "image" . ]]"
        args = [
          "crawl",
          "-sources", "[[ var "crawl_sources" . ]]",
          "-languages", "[[ var "crawl_languages" . ]]",
        ]
      }

      # A crawl answers SIGTERM by stopping collection and then spending up to
      # thirty minutes writing down what it already has — deliberately, because
      # interrupting a crawl should not throw away the hour before it. Nomad's
      # default kill_timeout is five seconds, which turns that design into a
      # SIGKILL and discards the final merged write along with the duplicate
      # merges that follow it.
      #
      # Thirty seconds is the most a client will honour without raising its own
      # max_kill_timeout, and it is enough for the checkpointed records to land.
      kill_timeout = "30s"

      env {service_ip" . ]]:[[ var "pg_port" . ]]/[[ var "pg_db_name" . ]]?sslmode=disable"
        MINIO_ENDPOINT       = "[[ var "service_ip" . ]]:[[ var "minio_port" . ]]"
        MINIO_ACCESS_KEY     = "[[ var "minio_root_user" . ]]"
        MINIO_USE_SSL        = "false"
        MUSEUM_BUCKET_NAME   = "[[ var "bucket_name" . ]]"
        KAFKA_BROKER_LOCAL   = "[[ var "service_ip" . ]]:[[ var "kafka_port" . ]]"
        KAFKA_TOPIC          = "[[ var "kafka_topic" . ]]"
        KAFKA_GROUP_ID       = "[[ var "kafka_group_id" . ]]"
        NOMINATIM_USER_AGENT = "[[ var "nominatim_user_agent" . ]]"
        TZ                   = "Europe/Stockholm"
      }

      # Secrets from a Nomad Variable, not the job spec: inline they were
      # readable via `nomad job inspect` and stored unencrypted in raft.
      # DATABASE_URL is assembled here because the password is embedded in it;
      # the non-secret parts remain pack variables.
      template {
        destination = "secrets/db.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{ with nomadVar "nomad/jobs/museum-crawl" }}
DATABASE_URL=postgres://[[ var "pg_user" . ]]:{{ .pg_password }}@[[ var "service_ip" . ]]:[[ var "pg_port" . ]]/[[ var "pg_db_name" . ]]?sslmode=disable
MINIO_SECRET_KEY={{ .minio_root_password }}
{{ end }}
EOH
      }


      # The reservation is unchanged; only the ceiling moves. The crawl holds
      # every record it has collected in memory until the end — that is what the
      # merger is — and with the default sources that is the whole catalogue,
      # around 200,000 records plus the name index built over their aliases.
      # Being OOM-killed ninety minutes into a two-hour run is a silent way to
      # waste the night, and the headroom costs nothing when it is not used.
      resources {
        cpu        = 1000
        memory     = 512
        memory_max = 1536
      }
    }

    task "reindex" {
      driver = "docker"

      lifecycle {
        hook    = "poststop"
        sidecar = false
      }

      config {
        image = "[[ var "image" . ]]"
        args  = ["reindex"]
      }

      env {service_ip" . ]]:[[ var "pg_port" . ]]/[[ var "pg_db_name" . ]]?sslmode=disable"
        MINIO_ENDPOINT     = "[[ var "service_ip" . ]]:[[ var "minio_port" . ]]"
        MINIO_ACCESS_KEY   = "[[ var "minio_root_user" . ]]"
        MINIO_USE_SSL      = "false"
        MUSEUM_BUCKET_NAME = "[[ var "bucket_name" . ]]"
        TZ                 = "Europe/Stockholm"
      }

      # Secrets from a Nomad Variable, not the job spec: inline they were
      # readable via `nomad job inspect` and stored unencrypted in raft.
      # DATABASE_URL is assembled here because the password is embedded in it;
      # the non-secret parts remain pack variables.
      template {
        destination = "secrets/db.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{ with nomadVar "nomad/jobs/museum-crawl" }}
DATABASE_URL=postgres://[[ var "pg_user" . ]]:{{ .pg_password }}@[[ var "service_ip" . ]]:[[ var "pg_port" . ]]/[[ var "pg_db_name" . ]]?sslmode=disable
MINIO_SECRET_KEY={{ .minio_root_password }}
{{ end }}
EOH
      }


      resources {
        cpu        = 800
        memory     = 512
        memory_max = 1024
      }
    }
  }
}
[[ end ]]
