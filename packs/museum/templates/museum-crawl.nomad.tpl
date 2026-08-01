[[ if var "enable_crawl" . ]]
# Rebuilds the catalogue from Wikidata, Wikipedia and OpenStreetMap, then loads
# the result into the database.
#
# Off by default (enable_crawl). A full crawl is hours of rate-limited work and
# writes 345,000 objects through MinIO and Kafka to the enricher; on a Pi that
# is shared with sixteen other allocations it is a decision, not a default.
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
        args  = ["crawl", "-sources", "[[ var "crawl_sources" . ]]"]
      }

      env {
        DATABASE_URL         = "postgres://[[ var "pg_user" . ]]:[[ var "pg_password" . ]]@[[ var "service_ip" . ]]:[[ var "pg_port" . ]]/[[ var "pg_db_name" . ]]?sslmode=disable"
        MINIO_ENDPOINT       = "[[ var "service_ip" . ]]:[[ var "minio_port" . ]]"
        MINIO_ACCESS_KEY     = "[[ var "minio_root_user" . ]]"
        MINIO_SECRET_KEY     = "[[ var "minio_root_password" . ]]"
        MINIO_USE_SSL        = "false"
        MUSEUM_BUCKET_NAME   = "[[ var "bucket_name" . ]]"
        KAFKA_BROKER_LOCAL   = "[[ var "service_ip" . ]]:[[ var "kafka_port" . ]]"
        KAFKA_TOPIC          = "[[ var "kafka_topic" . ]]"
        KAFKA_GROUP_ID       = "[[ var "kafka_group_id" . ]]"
        NOMINATIM_USER_AGENT = "[[ var "nominatim_user_agent" . ]]"
        TZ                   = "Europe/Stockholm"
      }

      resources {
        cpu        = 1000
        memory     = 512
        memory_max = 1024
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

      env {
        DATABASE_URL       = "postgres://[[ var "pg_user" . ]]:[[ var "pg_password" . ]]@[[ var "service_ip" . ]]:[[ var "pg_port" . ]]/[[ var "pg_db_name" . ]]?sslmode=disable"
        MINIO_ENDPOINT     = "[[ var "service_ip" . ]]:[[ var "minio_port" . ]]"
        MINIO_ACCESS_KEY   = "[[ var "minio_root_user" . ]]"
        MINIO_SECRET_KEY   = "[[ var "minio_root_password" . ]]"
        MINIO_USE_SSL      = "false"
        MUSEUM_BUCKET_NAME = "[[ var "bucket_name" . ]]"
        TZ                 = "Europe/Stockholm"
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
