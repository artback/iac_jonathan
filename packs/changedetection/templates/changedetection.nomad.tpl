job "changedetection" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "changedetection-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = 5000
        to     = 5000
      }
    }

    task "changedetection" {
      driver = "docker"

      config {
        image = "dgtlmoon/changedetection.io:[[ var "changedetection_version" . ]]"
        ports = ["http"]

        # Named volume — mount block, not the volumes shorthand (a relative
        # volumes source silently binds an ephemeral alloc dir).
        mount {
          type   = "volume"
          target = "/datastore"
          source = "[[ var "datastore_volume" . ]]"
        }
      }

      template {
        destination = "local/cd.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
          {{ with service "selenium" }}{{ with index . 0 }}
          WEBDRIVER_URL="http://{{ .Address }}:{{ .Port }}/wd/hub"
          {{ end }}{{ else }}
          WEBDRIVER_URL="http://100.116.81.88:4444/wd/hub"
          {{ end }}
          BASE_URL="[[ var "base_url" . ]]"
        EOH
      }

      resources {
        cpu    = 300
        memory     = 256
        memory_max = 512
      }

      service {
        name = "changedetection"
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
