# Rescrapes museum websites for the exhibitions currently on show.
#
# Separate from the service job because a periodic stanza applies to a whole
# job, and the API and enricher must not be periodic.
job "museum-refresh" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "batch"

  periodic {
    crons            = ["[[ var "refresh_cron" . ]]"]
    time_zone        = "UTC"
    # A refresh that overruns its window must not have a second copy started on
    # top of it: both would scrape the same sites, at twice the request rate
    # the museums' servers were meant to see.
    prohibit_overlap = true
  }

  group "refresh" {
    count = 1

    network {
      mode = "bridge"
    }

    task "refresh" {
      driver = "docker"

      config {
        image = "[[ var "image" . ]]"
        args = [
          "refresh",
          "-all",
          "-max-museums", "[[ var "refresh_max_museums" . ]]",
          # Well below the default of 8. The Pi shares one modest uplink with
          # sixteen other allocations, and this job is not the one that should
          # get to saturate it.
          "-concurrency", "[[ var "refresh_concurrency" . ]]",
        ]
      }

      env {
        NOMINATIM_USER_AGENT = "[[ var "nominatim_user_agent" . ]]"
        TZ                   = "Europe/Stockholm"
      }

      # Secret from a Nomad Variable, not the job spec: inline it was readable
      # via `nomad job inspect` to any read-capable token and stored
      # unencrypted in raft. The path is case-sensitive and must equal the job
      # ID exactly, or the task 403s and never starts.
      # DATABASE_URL is assembled here rather than above because the password is
      # embedded in it; the non-secret parts stay pack variables.
      template {
        destination = "secrets/db.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{ with nomadVar "nomad/jobs/museum-refresh" }}
DATABASE_URL=postgres://[[ var "pg_user" . ]]:{{ .pg_password }}@[[ var "service_ip" . ]]:[[ var "pg_port" . ]]/[[ var "pg_db_name" . ]]?sslmode=disable
{{ end }}
EOH
      }

      resources {
        cpu        = 500
        memory     = 384
        memory_max = 768
      }
    }
  }
}
