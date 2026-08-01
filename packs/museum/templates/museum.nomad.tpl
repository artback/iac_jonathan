# The museum catalogue: about 180,000 museums, the exhibitions currently on
# show, and the pipeline that maintains both.
#
# One image, one binary, six subcommands — the groups below differ only in the
# arguments they start it with.
#
# The groups run in separate network namespaces, so they address each other by
# the host's routable IP and the static ports declared here, not by container
# name as they do under docker compose.
job "museum" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  # -------------------------------------------------------------------------
  # PostgreSQL + PostGIS — the catalogue itself.
  #
  # Separate from the shared "postgres" job because the radius queries need
  # PostGIS and the similarity search needs pg_trgm, neither of which the
  # shared postgres:18-alpine has.
  # -------------------------------------------------------------------------
  group "db" {
    count = 1

    # A database is worth more than the seconds a restart saves. Give it room
    # to come back rather than failing the group.
    restart {
      attempts = 3
      interval = "5m"
      delay    = "20s"
      mode     = "delay"
    }

    network {
      mode = "bridge"
      port "db" {
        static = [[ var "pg_port" . ]]
        to     = 5432
      }
    }

    task "postgres" {
      driver = "docker"

      shutdown_delay = "5s"

      # Postgres needs to finish its shutdown checkpoint. Killed partway
      # through, it comes back needing crash recovery — on 850 MB of catalogue
      # that is a slow start at exactly the wrong moment.
      kill_timeout = "60s"

      config {
        image = "[[ var "pg_image" . ]]"
        ports = ["db"]
        # A mount stanza, not a "name:/path" entry in volumes. The docker
        # driver resolves a non-absolute source in volumes against the
        # allocation directory rather than as a Docker named volume, so
        # "[[ var "pg_volume" . ]]:/var/lib/postgresql/data" silently became a
        # per-allocation scratch directory: it survived task restarts, and
        # was destroyed the moment a deploy replaced the allocation. That is
        # how the first CD run emptied the catalogue.
        mount {
          type   = "volume"
          source = "[[ var "pg_volume" . ]]"
          target = "/var/lib/postgresql/data"
        }
      }

      env {
        POSTGRES_USER     = "[[ var "pg_user" . ]]"
        POSTGRES_PASSWORD = "[[ var "pg_password" . ]]"
        POSTGRES_DB       = "[[ var "pg_db_name" . ]]"
        # The image only initialises a cluster when this directory is empty, so
        # naming it explicitly is what makes a restored volume be adopted
        # rather than ignored.
        PGDATA = "/var/lib/postgresql/data"
      }

      resources {
        cpu        = 1000
        memory     = 768
        memory_max = 1536
      }

      service {
        name     = "museum-postgres"
        provider = "consul"
        # Pinned rather than left to Nomad's interface detection, which
        # advertised the client's Tailscale IPv6 for one of these services
        # while giving the others IPv4. Consul's check against that address
        # never completed, and the group sat forever at zero healthy.
        address  = "[[ var "service_ip" . ]]"
        port     = "db"
        tags     = ["museum", "postgres", "postgis"]

        check {
          name     = "alive"
          type     = "tcp"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
  }

[[ if var "enable_pipeline" . ]]
  # -------------------------------------------------------------------------
  # Kafka, single broker in KRaft mode.
  #
  # It carries exactly one thing: MinIO's notification that a raw record was
  # written, which is what wakes the enricher. The controller quorum and the
  # inter-broker listener point at localhost because there is only ever one
  # broker and it is talking to itself.
  # -------------------------------------------------------------------------
  group "broker" {
    count = 1

    network {
      mode = "bridge"
      port "kafka" {
        static = [[ var "kafka_port" . ]]
        to     = [[ var "kafka_port" . ]]
      }
    }

    task "kafka" {
      driver = "docker"

      shutdown_delay = "5s"
      kill_timeout   = "30s"

      config {
        image = "[[ var "kafka_image" . ]]"
        ports = ["kafka"]
        # A mount stanza, not a "name:/path" entry in volumes. The docker
        # driver resolves a non-absolute source in volumes against the
        # allocation directory rather than as a Docker named volume, so
        # "[[ var "kafka_volume" . ]]:/var/lib/kafka/data" silently became a
        # per-allocation scratch directory: it survived task restarts, and
        # was destroyed the moment a deploy replaced the allocation. That is
        # how the first CD run emptied the catalogue.
        mount {
          type   = "volume"
          source = "[[ var "kafka_volume" . ]]"
          target = "/var/lib/kafka/data"
        }
      }

      env {
        KAFKA_NODE_ID                = "1"
        KAFKA_PROCESS_ROLES          = "broker,controller"
        KAFKA_CONTROLLER_QUORUM_VOTERS = "1@localhost:9093"

        KAFKA_LISTENERS = "PLAINTEXT://:9092,EXTERNAL://:[[ var "kafka_port" . ]],CONTROLLER://:9093"
        # Clients are told the host address: MinIO and the enricher are in other
        # network namespaces and cannot reach the broker any other way.
        KAFKA_ADVERTISED_LISTENERS = "PLAINTEXT://localhost:9092,EXTERNAL://[[ var "service_ip" . ]]:[[ var "kafka_port" . ]]"

        KAFKA_LISTENER_SECURITY_PROTOCOL_MAP = "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT"
        KAFKA_CONTROLLER_LISTENER_NAMES      = "CONTROLLER"
        KAFKA_INTER_BROKER_LISTENER_NAME     = "PLAINTEXT"

        KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR         = "1"
        KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS         = "0"
        KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR = "1"
        KAFKA_TRANSACTION_STATE_LOG_MIN_ISR            = "1"
        CLUSTER_ID                                     = "museum-kalmar-cluster-1"

        # Left to itself the JVM sizes its heap from total system memory and
        # takes far more than this job is allowed.
        KAFKA_HEAP_OPTS = "[[ var "kafka_heap" . ]]"
      }

      resources {
        cpu        = 800
        memory     = 1024
        memory_max = 1536
      }

      service {
        name     = "museum-kafka"
        provider = "consul"
        # Pinned rather than left to Nomad's interface detection, which
        # advertised the client's Tailscale IPv6 for one of these services
        # while giving the others IPv4. Consul's check against that address
        # never completed, and the group sat forever at zero healthy.
        address  = "[[ var "service_ip" . ]]"
        port     = "kafka"
        tags     = ["museum", "kafka"]

        check {
          name     = "alive"
          type     = "tcp"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }

    # Creates the ingestion topic. poststart rather than prestart: it has to
    # talk to the broker beside it, which does not exist until the main task
    # is running.
    task "kafka-init" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      config {
        image = "[[ var "kafka_image" . ]]"
        args = [
          "bash", "-c",
          <<-EOT
          set -eu
          echo "Waiting for Kafka to be ready..."
          until /opt/kafka/bin/kafka-topics.sh --bootstrap-server $BROKER --list >/dev/null 2>&1; do
            echo '...waiting for kafka...'
            sleep 2
          done
          /opt/kafka/bin/kafka-topics.sh --create --if-not-exists \
            --topic $TOPIC --replication-factor 1 --partitions 1 \
            --bootstrap-server $BROKER
          echo "Kafka topic '$TOPIC' ensured."
          EOT
        ]
      }

      env {
        BROKER = "[[ var "service_ip" . ]]:[[ var "kafka_port" . ]]"
        TOPIC  = "[[ var "kafka_topic" . ]]"
      }

      resources {
        cpu    = 200
        memory = 320
      }
    }
  }

  # -------------------------------------------------------------------------
  # MinIO — the durable record. Every crawled museum is an object here; the
  # database is derived from it and can be rebuilt by "reindex".
  # -------------------------------------------------------------------------
  group "storage" {
    count = 1

    network {
      mode = "bridge"
      port "api" {
        static = [[ var "minio_port" . ]]
        to     = 9000
      }
      port "console" {
        static = [[ var "minio_console_port" . ]]
        to     = 9001
      }
    }

    # MinIO refuses to start when a configured notification target is
    # unreachable, so the broker has to be up first. Across groups there is no
    # depends_on to say that with — this waits instead.
    task "wait-for-kafka" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image = "alpine:3.20"
        args = [
          "sh", "-c",
          <<-EOT
          set -eu
          echo "Waiting for Kafka at $BROKER_HOST:$BROKER_PORT..."
          until nc -z $BROKER_HOST $BROKER_PORT; do
            echo '...waiting for kafka...'
            sleep 2
          done
          echo "Kafka is reachable."
          EOT
        ]
      }

      env {
        BROKER_HOST = "[[ var "service_ip" . ]]"
        BROKER_PORT = "[[ var "kafka_port" . ]]"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    task "minio" {
      driver = "docker"

      shutdown_delay = "5s"

      config {
        image = "[[ var "minio_image" . ]]"
        ports = ["api", "console"]
        args  = ["server", "/data", "--console-address", ":9001"]
        # A mount stanza, not a "name:/path" entry in volumes. The docker
        # driver resolves a non-absolute source in volumes against the
        # allocation directory rather than as a Docker named volume, so
        # "[[ var "minio_volume" . ]]:/data" silently became a
        # per-allocation scratch directory: it survived task restarts, and
        # was destroyed the moment a deploy replaced the allocation. That is
        # how the first CD run emptied the catalogue.
        mount {
          type   = "volume"
          source = "[[ var "minio_volume" . ]]"
          target = "/data"
        }
      }

      env {
        MINIO_ROOT_USER     = "[[ var "minio_root_user" . ]]"
        MINIO_ROOT_PASSWORD = "[[ var "minio_root_password" . ]]"

        # Declares the Kafka notification target. The bucket rule that actually
        # uses it is attached by minio-init below.
        MINIO_NOTIFY_KAFKA_ENABLE_1  = "on"
        MINIO_NOTIFY_KAFKA_BROKERS_1 = "[[ var "service_ip" . ]]:[[ var "kafka_port" . ]]"
        MINIO_NOTIFY_KAFKA_TOPIC_1   = "[[ var "kafka_topic" . ]]"
      }

      resources {
        cpu        = 500
        memory     = 512
        memory_max = 1024
      }

      service {
        name     = "museum-minio"
        provider = "consul"
        # Pinned rather than left to Nomad's interface detection, which
        # advertised the client's Tailscale IPv6 for one of these services
        # while giving the others IPv4. Consul's check against that address
        # never completed, and the group sat forever at zero healthy.
        address  = "[[ var "service_ip" . ]]"
        port     = "api"
        tags     = ["museum", "minio", "s3"]

        check {
          name     = "alive"
          type     = "http"
          path     = "/minio/health/live"
          interval = "20s"
          timeout  = "5s"
        }
      }
    }

    # Creates the bucket and attaches the event rule that feeds the enricher.
    task "minio-init" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      config {
        image = "[[ var "mc_image" . ]]"
        entrypoint = ["/bin/sh", "-c"]
        args = [
          <<-EOT
          set -eu
          echo "Waiting for MinIO to be ready..."
          until mc alias set local "http://$MINIO_HOST" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do
            echo '...waiting for minio...'
            sleep 2
          done

          mc mb --ignore-existing "local/$BUCKET"

[[ if var "seed_mode" . ]]
          # seed_mode: the notification rule is deliberately not attached, and
          # any rule left from a previous deploy is removed, so that mirroring
          # the existing catalogue in does not raise an event per object. See
          # the seed_mode variable for why that matters.
          #
          # The event and prefix must be repeated here. mc matches the rule to
          # remove on its whole definition, not on the ARN alone, so removing
          # by ARN fails with "no notification configuration matched" and
          # leaves the rule in place.
          mc event rm "local/$BUCKET" arn:minio:sqs::1:kafka --event put --prefix "raw_data/" 2>/dev/null || true

          # Verified rather than assumed. This is the only thing standing
          # between a bulk load and several hundred thousand requests to a
          # geocoder that permits one a second, and the first version of this
          # hid the removal's failure behind "|| true" — the rule survived and
          # only the migration script's own check caught it.
          if mc event ls "local/$BUCKET" | grep -q 'arn:minio:sqs'; then
            echo "SEED MODE FAILED: the notification rule is still attached." >&2
            mc event ls "local/$BUCKET" >&2
            exit 1
          fi
          echo "SEED MODE: bucket notification not attached for local/$BUCKET."
[[ else ]]
          # The prefix filter matters: the enricher writes its output back to
          # the same bucket under enriched_data/, and without this restriction
          # those writes would publish new events and feed the enricher its own
          # output in a loop.
          if mc event add "local/$BUCKET" arn:minio:sqs::1:kafka --event put --prefix "raw_data/" 2>/dev/null; then
            echo "Bucket notification created for local/$BUCKET (prefix raw_data/)."
          else
            echo "Bucket notification already present for local/$BUCKET."
          fi
[[ end ]]

          mc event ls "local/$BUCKET"
          EOT
        ]
      }

      env {
        # localhost, and the container port rather than the published one:
        # every task in a group shares one network namespace, so MinIO is a
        # loopback away. Addressing it by the host IP and its static port
        # instead sends the packet out to the host to be NAT'd straight back
        # into this same namespace, and that hairpin does not complete — the
        # symptom is this task waiting for a MinIO that is demonstrably up.
        MINIO_HOST          = "localhost:9000"
        MINIO_ROOT_USER     = "[[ var "minio_root_user" . ]]"
        MINIO_ROOT_PASSWORD = "[[ var "minio_root_password" . ]]"
        BUCKET              = "[[ var "bucket_name" . ]]"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
[[ end ]]

  # -------------------------------------------------------------------------
  # The HTTP API. The only group that has to be reachable from outside, and the
  # only one that needs nothing but the database — serve reads Postgres and
  # talks to the geocoder, never to MinIO or Kafka.
  # -------------------------------------------------------------------------
  group "api" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = [[ var "api_port" . ]]
        to     = 8090
      }
    }

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image = "[[ var "pg_image" . ]]"
        args = [
          "sh", "-c",
          "until pg_isready -h $PGHOST -p $PGPORT -U $PGUSER; do echo '...waiting for postgres...'; sleep 2; done",
        ]
      }

      env {
        PGHOST = "[[ var "service_ip" . ]]"
        PGPORT = "[[ var "pg_port" . ]]"
        PGUSER = "[[ var "pg_user" . ]]"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "api" {
      driver = "docker"

      # Deregistered from Consul before the container is signalled, so fabio
      # stops routing to it while it can still answer. Without this the requests
      # in flight during a redeploy are the ones that fail. Comfortably longer
      # than the check interval that would otherwise notice.
      shutdown_delay = "10s"

      # The binary drains for 20s on SIGTERM; killing it sooner cuts off
      # requests that are still inside their own deadline.
      kill_timeout = "30s"

      config {
        image = "[[ var "image" . ]]"
        ports = ["http"]
        args  = ["serve", "-addr", ":8090"]
      }

      env {
        DATABASE_URL         = "postgres://[[ var "pg_user" . ]]:[[ var "pg_password" . ]]@[[ var "service_ip" . ]]:[[ var "pg_port" . ]]/[[ var "pg_db_name" . ]]?sslmode=disable"
        NOMINATIM_USER_AGENT = "[[ var "nominatim_user_agent" . ]]"
        TZ                   = "Europe/Stockholm"
      }

      resources {
        cpu        = 500
        memory     = 256
        memory_max = 512
      }

      service {
        name     = "museum-api"
        provider = "consul"
        # Pinned rather than left to Nomad's interface detection, which
        # advertised the client's Tailscale IPv6 for one of these services
        # while giving the others IPv4. Consul's check against that address
        # never completed, and the group sat forever at zero healthy.
        address  = "[[ var "service_ip" . ]]"
        port     = "http"
        tags     = [[ var "service_tags" . | toStringList ]]

        check {
          name     = "alive"
          type     = "http"
          path     = "/livez"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
  }

[[ if var "enable_pipeline" . ]]
  # -------------------------------------------------------------------------
  # The enricher: a long-running consumer that geocodes each museum as it is
  # stored, and writes the result back under enriched_data/.
  # -------------------------------------------------------------------------
  group "enricher" {
    # Zero while seeding: every event it consumed during the mirror would be a
    # geocoder call for a museum that has already been enriched.
    count = [[ if var "seed_mode" . ]]0[[ else ]]1[[ end ]]

    network {
      mode = "bridge"
    }

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image = "[[ var "pg_image" . ]]"
        args = [
          "sh", "-c",
          "until pg_isready -h $PGHOST -p $PGPORT -U $PGUSER; do echo '...waiting for postgres...'; sleep 2; done",
        ]
      }

      env {
        PGHOST = "[[ var "service_ip" . ]]"
        PGPORT = "[[ var "pg_port" . ]]"
        PGUSER = "[[ var "pg_user" . ]]"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "enricher" {
      driver = "docker"

      config {
        image = "[[ var "image" . ]]"
        args  = ["enrich"]
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
        cpu        = 300
        memory     = 256
        memory_max = 512
      }
    }
  }
[[ end ]]
}
