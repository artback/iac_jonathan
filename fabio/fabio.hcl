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

variable "fabio_tags" {
  description = "The tags for the Fabio service."
  type        = list(string)
  default     = ["urlprefix-/"]
}

job "${var.job_name}" {
  datacenters = var.datacenters
  type        = var.type

  group "${var.group_name}" {
    network {
      port "lb" {
        static = var.lb_port
      }
      port "ui" {
        static = var.ui_port
      }
    }
    task "fabio" {
      driver = "docker"
      config {
        image        = var.image
        network_mode = "host"
        ports        = ["lb", "ui"]
      }

      resources {
        cpu    = var.cpu
        memory = var.memory
      }

      service {
        name = "fabio"
        tags = var.fabio_tags
        port = "lb"
      }
    }
  }
}
