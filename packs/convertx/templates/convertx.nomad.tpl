job "convertx" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "convertx-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = 5005
        to     = 3000
      }
    }

    task "convertx" {
      driver = "docker"

      config {
        image = "ghcr.io/c4illin/convertx:[[ var "convertx_version" . ]]"
        ports = ["http"]

        # Host bind (absolute path — safe with the volumes shorthand,
        # unlike named volumes which need a mount block).
        volumes = ["[[ var "data_dir" . ]]:/app/data"]
      }

      # ConvertX demands an account by default: / redirects to /setup and
      # refuses to convert anything until you create one. There is no password
      # to recover -- no account was ever made -- and a single-operator
      # converter on a private tailnet does not want a login at all.
      #
      # HTTP_ALLOWED is required alongside it: this is served over plain HTTP
      # on the tailnet, and without it ConvertX refuses the session cookie and
      # you land back at the login screen having apparently done nothing.
      env {
        ALLOW_UNAUTHENTICATED = "[[ var "allow_unauthenticated" . ]]"
        HTTP_ALLOWED          = "true"
      }

      resources {
        cpu    = 500
        memory     = 128
        memory_max = 512
      }

      service {
        name = "convertx"
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
