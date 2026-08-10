variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "telegram_token" {
  description = "Telegram bot token (secret — set in vars file). Needs its own bot: only one process may poll a token."
  type        = string
}

variable "chat_id" {
  description = "The only chat allowed to use the bot."
  type        = string
  default     = "485643205"
}

variable "calibre_url" {
  description = "Calibre-Web base URL, no trailing slash."
  type        = string
  default     = "https://seedking.nyx.usbx.me/calibre-web"
}

variable "calibre_user" {
  description = "Calibre-Web username (secret — set in vars file)."
  type        = string
}

variable "calibre_password" {
  description = "Calibre-Web password (secret — set in vars file)."
  type        = string
}

variable "silent" {
  description = "Deliver Telegram messages without sound."
  type        = string
  default     = "true"
}
