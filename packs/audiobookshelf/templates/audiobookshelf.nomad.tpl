job "audiobookshelf" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "audiobookshelf-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = 13378
        to     = 80
      }
    }

    task "audiobookshelf" {
      driver = "docker"

      config {
        image = "ghcr.io/advplyr/audiobookshelf:[[ var "abs_version" . ]]"
        ports = ["http"]

        # media libraries: host binds (absolute paths — volumes shorthand ok)
        volumes = [
          "[[ var "audiobooks_dir" . ]]:/audiobooks",
          "[[ var "podcasts_dir" . ]]:/podcasts",
        ]

        # app state: named volumes — mount blocks, not the volumes shorthand
        mount {
          type   = "volume"
          target = "/config"
          source = "[[ var "config_volume" . ]]"
        }
        mount {
          type   = "volume"
          target = "/metadata"
          source = "[[ var "metadata_volume" . ]]"
        }
      }

      env {
        TZ = "Europe/Stockholm"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "audiobookshelf"
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
