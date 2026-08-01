variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "node_exporter_version" {
  description = "The node-exporter version to run. Pin this — do not use latest."
  type        = string
  default     = "v1.12.1"
}
