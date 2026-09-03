# This job file defines a PostgreSQL service in Nomad.
job "postgres" {
  # Specifies the datacenters where the job can run.
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  # A group defines a set of tasks that should be co-located on the same client.
  group "postgres-group" {
    count = 1

    network {
      mode = "bridge"
      port "db" {
        static = [[ var "db_port" . ]]
      }
    }
    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:[[ var "pg_version" . ]]-alpine"
        ports = ["db"]
        # Named Docker volume. NOT the `volumes = ["name:path"]` shorthand:
        # Nomad treats a relative source there as a path inside the alloc dir,
        # which is deleted on GC — that's how the original data was lost.
        mounts = [
          {
            type     = "volume"
            source   = "[[ var "docker_volume_name" . ]]"
            target   = "/var/lib/postgresql"
            readonly = false
          }
        ]
      }

      env {
        POSTGRES_USER = "[[ var "pg_user" . ]]"
        POSTGRES_DB   = "[[ var "pg_db_name" . ]]"
      }

      # The password comes from a Nomad Variable rather than the job spec. Put
      # inline it was readable to any holder of a read-capable token via
      # `nomad job inspect`, and stored unencrypted in raft; here it is
      # encrypted at rest and reachable only by this job's workload identity.
      #
      #   nomad var put nomad/jobs/postgres pg_password=...
      #
      # The path is case-sensitive and must match the job ID exactly -- a
      # mismatch yields a 403 and a task that never starts.
      template {
        destination = "secrets/db.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{ with nomadVar "nomad/jobs/postgres" }}
POSTGRES_PASSWORD={{ .pg_password }}
{{ end }}
EOH
      }

      service {
        name = "postgres"
        tags = [
          "postgres"
        ]
        provider = "consul"
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