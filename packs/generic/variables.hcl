variable "job_name" {
  description = "Job name. Also used as the Consul service name unless service_name is set."
  type        = string
}

variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "count" {
  description = "Number of instances to run."
  type        = number
  default     = 1
}

variable "image" {
  description = "Docker image (including tag)."
  type        = string
}

variable "port" {
  description = "Container port the app listens on."
  type        = number
}

variable "static_port" {
  description = "Optional fixed host port. 0 = dynamic port (recommended; Fabio routes to it via Consul)."
  type        = number
  default     = 0
}

variable "service_name" {
  description = "Consul service name. Defaults to job_name when empty."
  type        = string
  default     = ""
}

variable "url_prefix" {
  description = "Fabio route path, e.g. \"/myapp\". Empty = no Fabio route. Adds tag: urlprefix-<path> strip=<path>."
  type        = string
  default     = ""
}

variable "strip_prefix" {
  description = "Whether Fabio should strip the url_prefix before proxying. Set false for apps that serve under a subpath themselves."
  type        = bool
  default     = true
}

variable "extra_tags" {
  description = "Additional Consul service tags."
  type        = list(string)
  default     = []
}

variable "env_vars" {
  description = "Environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "args" {
  description = "Optional container command args."
  type        = list(string)
  default     = []
}

variable "volumes" {
  description = "Docker host volumes, e.g. [\"/opt/myapp:/data\"]. Host path must exist on the node."
  type        = list(string)
  default     = []
}

variable "health_check_path" {
  description = "HTTP health check path. Empty = TCP check on the port instead."
  type        = string
  default     = ""
}

variable "cpu" {
  description = "CPU in MHz."
  type        = number
  default     = 200
}

variable "memory" {
  description = "Memory in MB."
  type        = number
  default     = 256
}
