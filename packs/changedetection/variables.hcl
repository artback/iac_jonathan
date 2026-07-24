variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "changedetection_version" {
  description = "The changedetection.io version to run. Pin this — do not use latest."
  type        = string
  default     = "0.55.8"
}

variable "datastore_volume" {
  description = "The docker named volume for /datastore. Reuses the volume from the pre-pack hand-run container."
  type        = string
  default     = "datastore-volume"
}

variable "base_url" {
  description = "External base URL used in notification links."
  type        = string
  default     = "http://100.116.81.88:5000"
}

variable "service_tags" {
  description = "The tags for the changedetection service."
  type        = list(string)
  default     = ["changedetection"]
}
