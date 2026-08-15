job "beszel" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  # 1. HUB: web UI + history database (PocketBase)
  group "hub-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = [[ var "hub_port" . ]]
        to     = 8090
      }
    }

    task "hub" {
      driver = "docker"

      config {
        image = "henrygd/beszel:[[ var "beszel_version" . ]]"
        ports = ["http"]

        # mount block, NOT volumes: the docker driver treats a non-absolute
        # volumes source as a path relative to the task dir, silently
        # creating an empty dir instead of using the named docker volume
        mount {
          type   = "volume"
          target = "/beszel_data"
          source = "[[ var "hub_data_volume" . ]]"
        }
      }

      env {
        TZ = "Europe/Stockholm"
        [[- if ne (var "auto_login" .) "" ]]
        AUTO_LOGIN = "[[ var "auto_login" . ]]"
        [[- end ]]
      }

      resources {
        cpu    = 200
        memory     = 128
        memory_max = 256
      }

      service {
        name = "beszel"
        port = "http"
        tags = [[ var "service_tags" . | toStringList ]]

        check {
          name     = "alive"
          type     = "http"
          path     = "/api/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }

  # 2. AGENT: host metrics. Host network for real NIC stats; privileged
  # (opt-out via agent_privileged) so smartctl can reach /dev for S.M.A.R.T.
  group "agent-group" {
    count = 1

    network {
      mode = "host"
    }

    task "agent" {
      driver = "docker"

      config {
        image        = "henrygd/beszel-agent:[[ var "beszel_version" . ]]"
        network_mode = "host"
        privileged   = [[ var "agent_privileged" . ]]
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro",
          [[- range $fs := (var "extra_filesystems" .) ]]
          "[[ $fs ]]:/extra-filesystems/[[ $fs | base ]]:ro",
          [[- end ]]
        ]

        # named docker volume (fingerprint) — must be a mount block, see hub
        mount {
          type   = "volume"
          target = "/var/lib/beszel-agent"
          source = "[[ var "agent_data_volume" . ]]"
        }
      }

      template {
        destination = "secrets/agent.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
          LISTEN="45876"
          HUB_URL="[[ var "agent_hub_url" . ]]"
          TOKEN="{{ with nomadVar "nomad/jobs/beszel" }}{{ .agent_token }}{{ end }}"
          KEY="{{ with nomadVar "nomad/jobs/beszel" }}{{ .agent_key }}{{ end }}"
          PRIMARY_SENSOR="[[ var "primary_sensor" . ]]"
          NICS="[[ var "nics" . ]]"
          DATA_DIR="/var/lib/beszel-agent"
        EOH
      }

      resources {
        cpu    = 200
        memory     = 128
        memory_max = 256
      }
    }
  }
}
