job "scriberr" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "scriberr-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        to = 8080
      }
    }

    task "scriberr" {
      driver = "docker"

      config {
        image = "ghcr.io/rishikanthc/scriberr:[[ var "scriberr_version" . ]]"
        ports = ["http"]
        volumes = [
          "[[ var "scriberr_data_volume" . ]]:/app/data",
          "[[ var "env_data_volume" . ]]:/app/whisperx-env",
        ]
      }

      env {
        PUID           = "[[ var "puid" . ]]"
        PGID           = "[[ var "pgid" . ]]"
        APP_ENV        = "production"
        ALLOWED_ORIGINS = "[[ var "allowed_origins" . ]]"
        SECURE_COOKIES  = [[ var "secure_cookies" . ]]
        ENABLE_DIARIZATION = [[ var "enable_diarization" . ]]
        HUGGINGFACE_ACCESS_TOKEN = "[[ var "huggingface_access_token" . ]]"
        ENABLE_CANARY = [[ var "enable_canary" . ]]
        ENABLE_PARAKEET = [[ var "enable_parakeet" . ]]
      }

      resources {
        cpu    = 1000
        memory = 2048
      }

      service {
        name = "scriberr"
        port = "http"
        tags = [[ var "service_tags" . | toStringList ]]

        check {
          name     = "alive"
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}