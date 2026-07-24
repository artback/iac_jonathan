variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "convertx_version" {
  description = "The ConvertX version to run. Pin this — do not use latest."
  type        = string
  default     = "v0.18.0"
}

variable "data_dir" {
  description = "Host directory for /app/data (accounts db + conversion history)."
  type        = string
  default     = "/home/dwight/convertx"
}

variable "service_tags" {
  description = "The tags for the convertx service."
  type        = list(string)
  default     = ["convertx"]
}
