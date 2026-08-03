variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "telegram_token" {
  description = "Telegram bot token (secret — set in vars file)."
  type        = string
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

variable "radarr_api_key" {
  description = "Radarr API key (secret — set in vars file)."
  type        = string
}

variable "sonarr_url" {
  description = "Sonarr base URL (no trailing slash)."
  type        = string
  default     = "https://seedking.nyx.usbx.me/sonarr"
}

variable "sonarr_api_key" {
  description = "Sonarr API key (secret — set in vars file)."
  type        = string
}
