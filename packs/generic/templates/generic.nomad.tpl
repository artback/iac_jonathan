job "[[ var "job_name" . ]]" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "[[ var "job_name" . ]]" {
    count = [[ var "count" . ]]

    network {
      port "http" {
[[- if gt (int (var "static_port" .)) 0 ]]
        static = [[ var "static_port" . ]]
[[- end ]]
        to = [[ var "port" . ]]
      }
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    service {
      name = "[[ or (var "service_name" .) (var "job_name" .) ]]"
      port = "http"
      tags = [
[[- if var "url_prefix" . ]]
        "urlprefix-[[ var "url_prefix" . ]][[ if var "strip_prefix" . ]] strip=[[ var "url_prefix" . ]][[ end ]]",
[[- end ]]
[[- range $tag := (var "extra_tags" .) ]]
        [[ $tag | quote ]],
[[- end ]]
      ]

      check {
        name     = "alive"
[[- if var "health_check_path" . ]]
        type     = "http"
        path     = "[[ var "health_check_path" . ]]"
[[- else ]]
        type     = "tcp"
[[- end ]]
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "[[ var "job_name" . ]]" {
      driver = "docker"

      config {
        image = "[[ var "image" . ]]"
        ports = ["http"]
[[- if var "args" . ]]
        args = [[ var "args" . | toStringList ]]
[[- end ]]
[[- if var "volumes" . ]]
        volumes = [[ var "volumes" . | toStringList ]]
[[- end ]]
      }

[[- if var "env_vars" . ]]

      env {
[[- range $k, $v := (var "env_vars" .) ]]
        [[ $k ]] = [[ $v | quote ]]
[[- end ]]
      }
[[- end ]]

      resources {
        cpu    = [[ var "cpu" . ]]
        memory = [[ var "memory" . ]]
      }
    }
  }
}
