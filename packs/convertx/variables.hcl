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

# Off by default upstream, on by default here. This service is reachable only
# from the tailnet, and the alternative is an account whose password exists
# purely to be forgotten. Set to "false" if convertx is ever published wider
# than the tailnet -- see the note in the pack about port 5005 and CNI.
variable "allow_unauthenticated" {
  description = "Skip ConvertX's login entirely (tailnet-only deployments)."
  type        = string
  default     = "true"
}
