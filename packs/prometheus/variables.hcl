variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "prometheus_version" {
  description = "The Prometheus version to run. Pin this — do not use latest."
  type        = string
  default     = "v3.13.2"
}

variable "data_volume" {
  description = "The docker named volume for the TSDB."
  type        = string
  default     = "prometheus_data"
}

variable "certs_dir" {
  description = "Host dir with world-readable nomad/consul client cert copies (created by the tls role)."
  type        = string
  default     = "/etc/certs/prometheus"
}

variable "service_tags" {
  description = "The tags for the prometheus service."
  type        = list(string)
  default     = ["urlprefix-/prometheus"]
}
