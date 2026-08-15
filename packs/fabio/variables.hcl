variable "job_name" {
  description = "The name of the Nomad job."
  type        = string
  default     = "fabio"
}

variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
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

variable "consul_addr" {
  description = "Consul HTTP address Fabio connects to. Fabio runs with host networking, so loopback reaches the node-local agent (which may be loopback-only under mTLS)."
  type        = string
  default     = "127.0.0.1:8500"
}
