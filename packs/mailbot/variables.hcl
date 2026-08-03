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

variable "categories" {
  description = "Classification categories: name → description fed to the LLM prompt."
  type        = map(string)
  default = {
    urgent     = "requires action or reply soon, deadlines, appointments, legal or contractual matters"
    job        = "job opportunities, recruiter outreach, application updates, interview scheduling"
    finance    = "bills, invoices, bank and payment notifications, taxes, insurance"
    personal   = "personal correspondence from real people"
    orders     = "order confirmations, shipping and delivery updates"
    newsletter = "newsletters, marketing, product updates, automated digests"
    other      = "anything that fits none of the above"
  }
}

variable "tracked" {
  description = "Categories that get detail extraction, an Obsidian note and a spot on the ranked top list."
  type        = list(string)
  default     = ["job"]
}

variable "profile" {
  description = "Who the fit score is scored against — edit to taste in vars."
  type        = string
  default     = "Software / platform engineer (Go, Kubernetes, Nomad, infrastructure), based in Marseille, open to remote EU roles."
}

variable "vault_dir" {
  description = "Host path of the Obsidian vault. Bot writes ONLY under '<vault>/Mail Triage/'."
  type        = string
  default     = "/home/dwight/Job applications"
}

variable "state_volume" {
  description = "Docker named volume for the sqlite triage log."
  type        = string
  default     = "mailbot_data"
}
