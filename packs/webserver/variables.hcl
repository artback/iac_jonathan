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

variable "webserver_port" {
  description = "The fixed host port for webserver."
  type        = number
  default     = 10000 
}

variable "service_name" {
  description = "The name of the service."
  type        = string
  default     = "webserver"
}

variable "service_tags" {
  description = "The tags for the service."
  type        = list(string)
  default     = ["urlprefix-/webserver strip=/webserver"]
}

variable "image" {
  description = "The Docker image to use."
  type        = string
  default     = "httpd:latest"
}

variable "index_html" {
  description = "The HTML content for index.html"
  type        = string
  default     = "<html><body><h1>Hello World</h1></body></html>"
}

