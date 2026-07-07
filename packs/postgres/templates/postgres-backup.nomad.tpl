# Nightly pg_dumpall to the host, 7-day rotation. Exists because the original
# postgres job ran without any volume and its data died with the container.
job "postgres-backup" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "batch"

  periodic {
    crons            = ["0 3 * * *"]
    prohibit_overlap = true
  }

  group "backup" {
    task "pg-dumpall" {
      driver = "docker"

      config {
        image   = "postgres:[[ var "pg_version" . ]]-alpine"
        volumes = ["[[ var "backup_dir" . ]]:/backups"]
        command = "sh"
        args = [
          "-c",
          "pg_dumpall -h $PGHOST -p $PGPORT -U $PGUSER | gzip > /backups/pg-dumpall-$(date +%u).sql.gz && ls -la /backups/"
        ]
      }

      template {
        destination = "local/pg.env"
        env         = true
        data        = <<EOH
          {{ with service "postgres" }}{{ with index . 0 }}
          PGHOST="{{ .Address }}"
          PGPORT="{{ .Port }}"
          {{ end }}{{ else }}
          PGHOST="100.116.81.88"
          PGPORT="5432"
          {{ end }}
          PGUSER="[[ var "pg_user" . ]]"
          PGPASSWORD="[[ var "pg_password" . ]]"
        EOH
      }

      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
