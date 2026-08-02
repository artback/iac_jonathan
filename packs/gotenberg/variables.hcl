variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "gotenberg_version" {
  description = "The Gotenberg version to run. Pin this — do not use latest."
  type        = string
  default     = "8.34.0"
}

variable "port" {
  description = "Static host port for the conversion API."
  type        = number
  default     = 3010
}
