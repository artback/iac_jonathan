variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "service_tags" {
  description = "Fabio routing tags — serves the dashboard at the root."
  type        = list(string)
  default     = ["urlprefix-/dashboard strip=/dashboard", "urlprefix-/ strip=/"]
}
