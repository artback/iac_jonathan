# Dumps the catalogue on a schedule.
#
# The shared "backup" job runs pg_dumpall against the shared postgres service
# and never sees this database, so the catalogue would otherwise be the one
# thing on the Pi with no backup at all — and it costs about four hours of
# rate-limited crawling to rebuild.
#
# Two copies, matching the shared job's convention: one on the NVMe beside the
# data, one on the USB drive, which is the copy that survives losing the disk.
job "museum-backup" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "batch"

  periodic {
    crons            = ["[[ var "backup_cron" . ]]"]
    time_zone        = "UTC"
    prohibit_overlap = true
  }

  group "backup" {
    count = 1

    task "backup" {
      driver = "docker"

      config {
        image = "[[ var "pg_image" . ]]"

        volumes = [
          "[[ var "local_backup_dir" . ]]:/backups-local",
          "[[ var "usb_backup_dir" . ]]:/backups-usb",
        ]

        # No ${VAR} braces anywhere in this script: HCL heredocs eat them
        # (see gotcha: HCL2 $${} escaping is unreliable through nomad-pack).
        args = [
          "sh", "-c",
          <<-EOT
          set -eu
          mkdir -p /backups-local/museum /backups-usb/museum

          STAMP=$(date +%Y%m%d-%H%M%S)

          # Written to a partial name first: a dump interrupted midway must
          # never be mistaken for a complete one, which is exactly the file you
          # would reach for in the moment it matters.
          PARTIAL=/backups-local/museum/.museum-$STAMP.dump.partial
          FINAL=/backups-local/museum/museum-$STAMP.dump

          pg_dump --format=custom --compress=9 -f $PARTIAL
          test -s $PARTIAL
          mv $PARTIAL $FINAL
          cp $FINAL /backups-usb/museum/

          echo "wrote $(basename $FINAL) ($(du -h $FINAL | cut -f1))"

          # Prune both copies. Without this the thing protecting the disk is
          # what eventually fills it.
          for DIR in /backups-local/museum /backups-usb/museum; do
            COUNT=$(find $DIR -maxdepth 1 -name 'museum-*.dump' | wc -l)
            if [ "$COUNT" -gt "$KEEP" ]; then
              find $DIR -maxdepth 1 -name 'museum-*.dump' | sort | head -n $((COUNT - KEEP)) |
                while read -r OLD; do
                  rm -f "$OLD"
                  echo "pruned $(basename $OLD)"
                done
            fi
          done

          ls -la /backups-local/museum /backups-usb/museum
          EOT
        ]
      }

      env {
        PGHOST     = "[[ var "service_ip" . ]]"
        PGPORT     = "[[ var "pg_port" . ]]"
        PGUSER     = "[[ var "pg_user" . ]]"
        PGPASSWORD = "[[ var "pg_password" . ]]"
        PGDATABASE = "[[ var "pg_db_name" . ]]"
        KEEP       = "[[ var "backup_keep" . ]]"
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}
