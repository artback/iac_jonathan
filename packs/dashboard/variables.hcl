variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "miniflux_upstream" {
  description = "Miniflux base URL the news proxy forwards to."
  type        = string
  default     = "http://100.116.81.88:8081"
}

variable "miniflux_api_key" {
  description = "Miniflux API key for the read-only news proxy (secret — set in vars file)."
  type        = string
}

variable "service_tags" {
  description = "Fabio routing tags — serves the dashboard at the root."
  type        = list(string)
  default     = ["urlprefix-/dashboard strip=/dashboard", "urlprefix-/ strip=/"]
}
