job "backup" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "batch"

  periodic {
    crons            = ["[[ var "cron" . ]]"]
    time_zone        = "UTC"
    prohibit_overlap = true
  }

  group "backup-group" {
    count = 1

    task "backup" {
      driver = "docker"

      config {
        image = "postgres:18-alpine"

        volumes = [
          "[[ var "local_backup_dir" . ]]:/backups-local",
          "[[ var "usb_backup_dir" . ]]:/backups-usb",
          [[- range $name, $path := (var "app_state_paths" .) ]]
          "[[ $path ]]:/state/[[ $name ]]:ro",
          [[- end ]]
        ]

        # No ${VAR} braces anywhere in this script: HCL heredocs eat them
        # (see gotcha: HCL2 $${} escaping is unreliable through nomad-pack).
        # Note: the beszel/n8n sqlite files are copied live (crash-consistent,
        # good enough here); postgres itself is dumped properly via pg_dumpall.
        args = [
          "sh", "-c",
          <<-EOT
          set -e
          DOW=$(date +%u)
          mkdir -p /backups-local/postgres /backups-local/app-state /backups-usb/postgres /backups-usb/app-state
          pg_dumpall -h $PGHOST -p $PGPORT -U $PGUSER | gzip > /backups-local/postgres/pg-dumpall-$DOW.sql.gz
          test -s /backups-local/postgres/pg-dumpall-$DOW.sql.gz
          tar czf /backups-local/app-state/app-state-$DOW.tar.gz -C /state .
          cp /backups-local/postgres/pg-dumpall-$DOW.sql.gz /backups-usb/postgres/
          cp /backups-local/app-state/app-state-$DOW.tar.gz /backups-usb/app-state/
          echo "=== backup $DOW done ==="
          ls -la /backups-local/postgres /backups-local/app-state /backups-usb/postgres /backups-usb/app-state
          EOT
        ]
      }

      template {
        destination = "secrets/pg.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
          {{ with service "postgres" }}{{ with index . 0 }}
          PGHOST="{{ .Address }}"
          PGPORT="{{ .Port }}"
          {{ end }}{{ else }}
          PGHOST="100.116.81.88"
          PGPORT="5432"
          {{ end }}
          PGUSER="[[ var "pg_user" . ]]"
          PGPASSWORD="{{ with nomadVar "nomad/jobs/backup" }}{{ .pg_password }}{{ end }}"
        EOH
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
