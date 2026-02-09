job "fabio" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "[[ var "type" . ]]"

  group "fabio" {
    restart {
      attempts = 3
      interval = "1m"
      delay    = "15s"
      mode     = "delay"
    }
    network {
      mode = "bridge"

      port "lb" {
        static = [[ var "lb_port" . ]]
        to     = 9999
      }
      port "ui" {
        static = [[ var "ui_port" . ]]
        to     = 9998
      }
    }

    task "fabio" {
      driver = "docker"
      env {
        CONSUL_IP = "[[ var "service_ip" . ]]"
      }
      config {
        image = "[[ var "image" . ]]"
        ports = ["lb", "ui"]
        args = [
          // Forces Fabio's service IP to the Tailscale IP
          "-proxy.localip=[[ var "service_ip" . ]]",

          // Forces the Consul connection address to the host's routable IP
          "-registry.consul.addr=[[ var "service_ip" . ]]:8500",
        ]
      }
      resources {
        cpu    = [[ var "cpu" . ]]
        memory = [[ var "memory" . ]]
      }
    }
  }
}