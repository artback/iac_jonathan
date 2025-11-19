variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["dc1"]
}

variable "count" {
  description = "The number of instances to run."
  type        = number
  default     = 1
}

variable "port" {
  description = "The port for n8n."
  type        = number
  default     = 5678
}

variable "image" {
  description = "The Docker image to use."
  type        = string
  default     = "docker.n8n.io/n8nio/n8n"
}

variable "cpu" {
  description = "The CPU resources to allocate."
  type        = number
  default     = 500 # n8n can be resource-intensive
}

variable "memory" {
  description = "The memory resources to allocate."
  type        = number
  default     = 512 # n8n can be resource-intensive
}

job "n8n" {
  datacenters = var.datacenters
  type        = "service"

  group "n8n" {
    count = var.count
    network {
      port "http" {
        static = var.port
      }
    }

    service {
      name = "n8n"
      port = "http"
      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "n8n" {
      driver = "docker"
      config {
        image = var.image
        ports = ["http"]
      }
      resources {
        cpu    = var.cpu
        memory = var.memory
      }
    }
  }
}
