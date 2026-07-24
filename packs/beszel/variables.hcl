variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "beszel_version" {
  description = "The version of Beszel (hub and agent) to run. Pin this — do not use latest."
  type        = string
  default     = "0.18.7"
}

variable "hub_data_volume" {
  description = "The docker volume for hub data (PocketBase db, history)."
  type        = string
  default     = "beszel_vol"
}

variable "hub_port" {
  description = "The static host port for the hub UI."
  type        = number
  default     = 8090
}

variable "service_tags" {
  description = "The tags for the beszel hub service."
  type        = list(string)
  default     = []
}

variable "auto_login" {
  description = "Email of the user to auto-login every visitor as (skip login page). Only safe because :8090 is tailnet-only. Empty disables."
  type        = string
  default     = ""
}

variable "agent_data_volume" {
  description = "The docker volume for agent data (fingerprint). Reuse to keep system identity."
  type        = string
  default     = "beszel_agent_data"
}

variable "agent_hub_url" {
  description = "The hub URL the agent connects to via WebSocket."
  type        = string
  default     = "http://100.116.81.88:8090"
}

variable "agent_token" {
  description = "The WebSocket registration token for the agent (secret — set in vars file)."
  type        = string
}

variable "agent_key" {
  description = "The hub's public SSH key(s) for agent authentication."
  type        = string
}

variable "agent_privileged" {
  description = "Run the agent privileged. Required for S.M.A.R.T. disk health (device access)."
  type        = bool
  default     = true
}

variable "extra_filesystems" {
  description = "Host mount points to monitor as extra filesystems (mounted ro under /extra-filesystems)."
  type        = list(string)
  default     = ["/mnt/usbdrive"]
}

variable "primary_sensor" {
  description = "Temperature sensor shown in the systems table."
  type        = string
  default     = "cpu_thermal"
}

variable "nics" {
  description = "Network interface filter. A leading - makes the whole list a blacklist."
  type        = string
  default     = "-veth*,docker*,nomad"
}
