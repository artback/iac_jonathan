variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "watchtower_version" {
  description = "The watchtower version to run. Pin this — do not use latest."
  type        = string
  default     = "1.7.1"
}

variable "poll_interval" {
  description = "Seconds between update checks (86400 = daily)."
  type        = number
  default     = 86400
}
