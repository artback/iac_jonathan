variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "imap_host" {
  description = "IMAP server."
  type        = string
  default     = "imap.mail.me.com"
}

variable "imap_user" {
  description = "IMAP account."
  type        = string
  default     = "jonathan_artback@icloud.com"
}

variable "imap_password" {
  description = "IMAP app-specific password (secret — set in vars file)."
  type        = string
}

variable "telegram_token" {
  description = "Telegram bot token used for sending (secret — set in vars file). Send-only: safe to share with printbot."
  type        = string
}

variable "chat_id" {
  description = "Telegram chat that receives pings and the digest."
  type        = string
  default     = "485643205"
}

variable "ollama_url" {
  description = "Ollama endpoint for classification."
  type        = string
  default     = "http://100.116.81.88:11434"
}

variable "model" {
  description = "Ollama model used for classification."
  type        = string
  default     = "llama3.2:3b"
}

variable "digest_hour" {
  description = "Local hour (0-23) for the daily digest."
  type        = number
  default     = 8
}

variable "state_volume" {
  description = "Docker named volume for the sqlite triage log."
  type        = string
  default     = "mailbot_data"
}
