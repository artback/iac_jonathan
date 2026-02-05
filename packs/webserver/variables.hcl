variable "job_name" {
  description = "The name of the job."
  type        = string
  default     = "webserver"
}

variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "count" {
  description = "The number of instances to run."
  type        = number
  default     = 3
}

variable "service_name" {
  description = "The name of the service."
  type        = string
  default     = "apache-webserver"
}

variable "tags" {
  description = "The tags for the service."
  type        = list(string)
  default     = ["urlprefix-/"]
}

variable "image" {
  description = "The Docker image to use."
  type        = string
  default     = "httpd:latest"
}
