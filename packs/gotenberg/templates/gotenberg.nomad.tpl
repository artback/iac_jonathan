job "gotenberg" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "gotenberg-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = [[ var "port" . ]]
        to     = 3000
      }
    }

    task "gotenberg" {
      driver = "docker"

      config {
        image = "gotenberg/gotenberg:[[ var "gotenberg_version" . ]]"
        ports = ["http"]
      }

      resources {
        cpu        = 500
        memory     = 256
        memory_max = 1024
      }

      service {
        name = "gotenberg"
        port = "http"

        check {
          name     = "alive"
          type     = "http"
          path     = "/health"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
  }
}
