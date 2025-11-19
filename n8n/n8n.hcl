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

variable "n8n_tags" {
  description = "The tags for the n8n service."
  type        = list(string)
  default     = ["urlprefix-/n8n"]
}

variable "volume_id" {
  description = "The ID of the host volume to use for data persistence."
  type        = string
  default     = "n8n_data"
}

variable "host_volume_name" {
  description = "The name of the host volume on the Nomad client."
  type        = string
  default     = "/opt/n8n-data"
}

job "n8n" {
  datacenters = var.datacenters
  type        = "service"

  group "n8n" {
    count = var.count
    
    volume "${var.volume_id}" {
      type      = "host"
      source    = var.host_volume_name
      read_only = false
    }

    network {
      port "http" {
        static = var.port
      }
    }

    service {
      name = "n8n"
      tags = var.n8n_tags
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
      volume_mount {
        volume      = var.volume_id
        destination = "/home/node/.n8n"
        read_only   = false
      }
    }
  }
}
