variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "telegram_token" {
  description = "Telegram bot token from @BotFather (secret — set in vars file)."
  type        = string
}

variable "allowed_chat_ids" {
  description = "Comma-separated Telegram chat IDs allowed to print. Empty = bot replies to anyone with their ID but prints nothing (discovery mode)."
  type        = string
  default     = ""
}

variable "cups_server" {
  description = "CUPS server host:port the bot submits jobs to."
  type        = string
  default     = "100.116.81.88:631"
}

variable "printer" {
  description = "CUPS queue name."
  type        = string
  default     = "HP_ENVY_6000"
}
