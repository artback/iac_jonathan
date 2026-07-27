job "searxng" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "searxng-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = 8888
        to     = 8080
      }
    }

    task "searxng" {
      driver = "docker"

      config {
        image = "searxng/searxng:[[ var "searxng_version" . ]]"
        ports = ["http"]

        # named volume — mount block, not the volumes shorthand
        mount {
          type   = "volume"
          target = "/etc/searxng"
          source = "[[ var "config_volume" . ]]"
        }
      }

      template {
        destination = "secrets/searxng.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
          SEARXNG_BASE_URL="[[ var "base_url" . ]]"
          SEARXNG_SECRET="[[ var "secret_key" . ]]"
          TZ="Europe/Stockholm"
        EOH
      }

      resources {
        cpu    = 300
        memory = 512
      }

      service {
        name = "searxng"
        port = "http"
        tags = [[ var "service_tags" . | toStringList ]]

        check {
          name     = "alive"
          type     = "http"
          path     = "/healthz"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
  }
}
