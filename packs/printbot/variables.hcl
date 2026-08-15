variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "allowed_chat_ids" {
  description = "Comma-separated Telegram chat IDs allowed to print. Empty = bot replies to anyone with their ID but prints nothing (discovery mode)."
  type        = string
  default     = ""
}

variable "state_volume" {
  description = "Docker named volume for dynamic membership state (invited members live here, not in the repo)."
  type        = string
  default     = "printbot_data"
}

variable "cups_server" {
  description = "CUPS server host:port the bot submits jobs to."
  type        = string
  default     = "100.116.81.88:631"
}

variable "gotenberg_url" {
  description = "Gotenberg conversion API for office documents (empty disables conversion)."
  type        = string
  default     = "http://100.116.81.88:3010"
}

variable "printer" {
  description = "CUPS queue name."
  type        = string
  default     = "HP_ENVY_6000"
}
