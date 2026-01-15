variable "job_name" {
  description = "The name of the Nomad job."
  type        = string
  default     = "fabio"
}

variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["dc1"]
}

variable "type" {
  description = "The type of job."
  type        = string
  default     = "system"
}

variable "group_name" {
  description = "The name of the group within the job."
  type        = string
  default     = "fabio"
}

variable "lb_port" {
  description = "The port for the load balancer."
  type        = number
  default     = 9999
}

variable "ui_port" {
  description = "The port for the UI."
  type        = number
  default     = 9998
}

variable "image" {
  description = "The Docker image to use."
  type        = string
  default     = "fabiolb/fabio"
}

variable "cpu" {
  description = "The CPU resources to allocate."
  type        = number
  default     = 200
}

variable "memory" {
  description = "The memory resources to allocate."
  type        = number
  default     = 128
}

variable "service_ip" {
  description = "The IP address used for service discovery"
  type        = string

}

job "fabio" {
  datacenters = var.datacenters
  type        = var.type

  group "fabio" {
    restart {
      attempts = 3
      interval = "1m"
      delay    = "15s"
      mode     = "delay"
    }
    network {
      mode = "bridge"

      port "lb" {
        static = var.lb_port
        to     = 9999
      }
      port "ui" {
        static = var.ui_port
        to     = 9998
      }
    }

    task "fabio" {
      driver = "docker"
      env {
        CONSUL_IP = var.service_ip
      }
      config {
        image = var.image
        ports = ["lb", "ui"]
        args = [
          // Forces Fabio's service IP to the Tailscale IP
          "-proxy.localip=${var.service_ip}",

          // Forces the Consul connection address to the host's routable IP
          "-registry.consul.addr=${var.service_ip}:8500",
        ]
      }
      resources {
        cpu    = var.cpu
        memory = var.memory
      }
    }
  }
}
