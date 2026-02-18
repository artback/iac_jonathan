job "scriberr" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "scriberr-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = [[ var "scriberr_port" . ]]
        to     = 8080
      }
    }

    task "scriberr" {
      driver = "docker"

      config {
        image = "ghcr.io/rishikanthc/scriberr:[[ var "scriberr_version" . ]]"
        ports = ["http"]
        volumes = [
          "[[ var "scriberr_data_volume" . ]]:/app/data",
          "[[ var "env_data_volume" . ]]:/app/storage",
        ]
      }

      env {
        PUID           = "[[ var "puid" . ]]"
        PGID           = "[[ var "pgid" . ]]"
        APP_ENV        = "production"
        PYTHON_ENV_PATH = "/app/data/whisperx-env"
        ALLOWED_ORIGINS = "[[ var "allowed_origins" . ]]"
        SECURE_COOKIES  = [[ var "secure_cookies" . ]]
        DB_PATH         = "/app/data/scriberr.db"
        UPLOAD_DIR      = "/app/data/uploads"
        TRANSCRIPT_DIR  = "/app/data/transcripts"
        WHISPER_MODEL   = "base"
        ENABLE_DIARIZATION = [[ var "enable_diarization" . ]]
        HUGGINGFACE_ACCESS_TOKEN = "[[ var "huggingface_access_token" . ]]"
        ENABLE_CANARY = [[ var "enable_canary" . ]]
        ENABLE_PARAKEET = [[ var "enable_parakeet" . ]]
      }

      resources {
        cpu    = 1000
        memory = 3072
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