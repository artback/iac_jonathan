job "[[ var "job_name" . ]]" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type = "service"

  group "webserver" {
    count = [[ var "count" . ]]
    
    network {
      # Maps a dynamic host port to Nginx internal port 80
      port "http" {
        to = 80
      }
    }

    service {
      name = "[[ var "service_name" . ]]"
      tags = [[ var "service_tags" . | toStringList ]]
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
      delay    = "15s"
      mode     = "fail"
    }

    task "nginx" {
      driver = "docker"
      config {
        # Ensure your pack variables use "nginx:alpine" for this to work
        image = "[[ var "image" . ]]"
        ports = ["http"]
        
        # FIX: Mount the index.html into the Nginx default directory
        mounts = [
          {
            type   = "bind"
            source = "local/index.html"
            target = "/usr/local/apache2/htdocs/index.html"
          }
        ]
      }

      template {
        data = <<EOH
{{ "[[ var "index_html" . ]]" | base64Decode }}
EOH
        destination = "local/index.html"
      }
    }
  }
}
