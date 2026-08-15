variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "searxng_version" {
  description = "The SearXNG image tag (dated tags; no stable releases). Pin this."
  type        = string
  default     = "2026.7.25-0909dbc9e"
}

variable "base_url" {
  description = "Public base URL of the instance."
  type        = string
  default     = "http://100.116.81.88:8888/"
}

variable "config_volume" {
  description = "The docker named volume for /etc/searxng."
  type        = string
  default     = "searxng_data"
}

variable "service_tags" {
  description = "The tags for the searxng service."
  type        = list(string)
  default     = ["searxng"]
}
