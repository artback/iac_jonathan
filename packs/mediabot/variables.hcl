variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "allowed_chat_ids" {
  description = "Comma-separated Telegram chat IDs allowed to use the bot."
  type        = string
  default     = ""
}

variable "radarr_url" {
  description = "Radarr base URL (no trailing slash)."
  type        = string
  default     = "https://seedking.nyx.usbx.me/radarr"
}

variable "sonarr_url" {
  description = "Sonarr base URL (no trailing slash)."
  type        = string
  default     = "https://seedking.nyx.usbx.me/sonarr"
}
