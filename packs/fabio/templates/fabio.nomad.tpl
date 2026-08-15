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
      # Host networking (matches the live job): Fabio must reach the
      # node-local Consul on loopback, which bridge mode can't.
      port "lb" {
        static = [[ var "lb_port" . ]]
      }
      port "ui" {
        static = [[ var "ui_port" . ]]
      }
    }

    task "fabio" {
      driver = "docker"
      env {
        CONSUL_IP = "[[ var "service_ip" . ]]"
      }
      config {
        image        = "[[ var "image" . ]]"
        network_mode = "host"
        ports        = ["lb", "ui"]
        args = [
          // Forces Fabio's service IP to the Tailscale IP
          "-proxy.localip=[[ var "service_ip" . ]]",

          "-registry.consul.addr=[[ var "consul_addr" . ]]",
        ]
      }
      resources {
        cpu    = [[ var "cpu" . ]]
        memory = [[ var "memory" . ]]
      }
    }
  }
}