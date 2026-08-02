job "node-exporter" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "system"

  group "node-exporter-group" {
    network {
      port "metrics" {
        static = 9100
      }
    }

    task "node-exporter" {
      driver = "docker"

      config {
        image        = "prom/node-exporter:[[ var "node_exporter_version" . ]]"
        network_mode = "host"
        args = [
          "--path.rootfs=/host",
          "--web.listen-address=:9100",
        ]
        volumes = [
          "/proc:/host/proc:ro",
          "/sys:/host/sys:ro",
          "/:/host:ro,rslave",
        ]
      }

      resources {
        cpu    = 100
        memory = 64
      }

      service {
        name = "node-exporter"
        port = "metrics"

        check {
          name     = "alive"
          type     = "http"
          path     = "/metrics"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
  }
}
