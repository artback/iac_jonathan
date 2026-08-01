job "watchtower" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "system"

  group "watchtower-group" {
    network {
      mode = "bridge"
    }

    task "watchtower" {
      driver = "docker"

      config {
        image   = "containrrr/watchtower:[[ var "watchtower_version" . ]]"
        volumes = ["/var/run/docker.sock:/var/run/docker.sock"]
      }

      env {
        WATCHTOWER_CLEANUP         = "true"
        WATCHTOWER_INCLUDE_STOPPED = "false"
        WATCHTOWER_NO_RESTART      = "false"
        WATCHTOWER_POLL_INTERVAL   = "[[ var "poll_interval" . ]]"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
