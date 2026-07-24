job "selenium" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "selenium-group" {
    count = 1

    network {
      mode = "bridge"
      port "webdriver" {
        static = 4444
        to     = 4444
      }
      port "vnc" {
        static = 7900
        to     = 7900
      }
    }

    task "selenium" {
      driver = "docker"

      config {
        image = "[[ var "selenium_image" . ]]"
        ports = ["webdriver", "vnc"]

        # Chromium needs a big /dev/shm or tabs crash
        shm_size = 2147483648
      }

      env {
        SE_NODE_MAX_SESSIONS    = "[[ var "max_sessions" . ]]"
        SE_NODE_SESSION_TIMEOUT = "[[ var "session_timeout" . ]]"
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      service {
        name = "selenium"
        port = "webdriver"
        tags = ["selenium"]

        check {
          name     = "grid-ready"
          type     = "http"
          path     = "/status"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
  }
}
