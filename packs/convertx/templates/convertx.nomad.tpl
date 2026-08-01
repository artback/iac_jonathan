job "convertx" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "convertx-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = 5005
        to     = 3000
      }
    }

    task "convertx" {
      driver = "docker"

      config {
        image = "ghcr.io/c4illin/convertx:[[ var "convertx_version" . ]]"
        ports = ["http"]

        # Host bind (absolute path — safe with the volumes shorthand,
        # unlike named volumes which need a mount block).
        volumes = ["[[ var "data_dir" . ]]:/app/data"]
      }

      resources {
        cpu    = 500
        memory     = 128
        memory_max = 512
      }

      service {
        name = "convertx"
        port = "http"
        tags = [[ var "service_tags" . | toStringList ]]

        check {
          name     = "alive"
          type     = "http"
          path     = "/"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
  }
}
