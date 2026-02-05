job "webserver" {
  datacenters = var.datacenters
  type = "service"

  group "webserver" {
    count = var.count
    network {
      port "http" {}
    }

    service {
      name = var.service_name
      tags = var.tags
      port = "http"
      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    restart {
      attempts = 2
      interval = "30m"
      delay = "15s"
      mode = "fail"
    }

    task "apache" {
      driver = "docker"
      config {
        image = var.image
        ports = ["http"]
      }
    }
  }
}
