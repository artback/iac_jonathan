variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["dc1"]
}

variable "type" {
  description = "The type of job."
  type        = string
  default     = "service"
}

variable "count" {
  description = "The number of instances to run."
  type        = number
  default     = 3
}

variable "http_port" {
  description = "The port for HTTP traffic."
  type        = number
  default     = 80
}

variable "service_name" {
  description = "The name of the service."
  type        = string
  default     = "apache-webserver"
}

variable "service_tags" {
  description = "The tags for the service."
  type        = list(string)
  default     = ["urlprefix-/"]
}

variable "check_name" {
  description = "The name of the health check."
  type        = string
  default     = "alive"
}

variable "check_type" {
  description = "The type of the health check."
  type        = string
  default     = "http"
}

variable "check_path" {
  description = "The path for the health check."
  type        = string
  default     = "/"
}

variable "check_interval" {
  description = "The interval for the health check."
  type        = string
  default     = "10s"
}

variable "check_timeout" {
  description = "The timeout for the health check."
  type        = string
  default     = "2s"
}

variable "restart_attempts" {
  description = "The number of restart attempts."
  type        = number
  default     = 2
}

variable "restart_interval" {
  description = "The interval for restart attempts."
  type        = string
  default     = "30m"
}

variable "restart_delay" {
  description = "The delay between restart attempts."
  type        = string
  default     = "15s"
}

variable "restart_mode" {
  description = "The restart mode."
  type        = string
  default     = "fail"
}

variable "image" {
  description = "The Docker image to use."
  type        = string
  default     = "httpd:latest"
}

job "webserver" {
  datacenters = var.datacenters
  type        = var.type

  group "webserver" {
    count = var.count
    network {
      port "http" {
        to = var.http_port
      }
    }

    service {
      name = var.service_name
      tags = var.service_tags
      port = "http"
      check {
        name     = var.check_name
        type     = var.check_type
        path     = var.check_path
        interval = var.check_interval
        timeout  = var.check_timeout
      }
    }

    restart {
      attempts = var.restart_attempts
      interval = var.restart_interval
      delay    = var.restart_delay
      mode     = var.restart_mode
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
