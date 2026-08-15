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
        POSTGRES_USER     = "[[ var "pg_user" . ]]"
        POSTGRES_PASSWORD = "[[ var "pg_password" . ]]" # Best practice is to use Nomad Secrets/Vault for this
        POSTGRES_DB       = "[[ var "pg_db_name" . ]]"
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