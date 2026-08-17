variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "image" {
  description = "Base image. Slim has no git, which is why start.sh installs from a release tarball rather than git+https."
  type        = string
  default     = "python:3.12-slim"
}

variable "stock_change_version" {
  description = "Tag of artback/stock-change to install. Pinned so an unattended restart cannot pull an untested main."
  type        = string
  default     = "v0.10.2"
}

variable "holdings" {
  description = "Ticker to share count. PRIVATE — set in vars/stock-bot.hcl, which is gitignored. This repository is public, so it must never carry a real portfolio."
  type        = map(number)
  default     = {}
}

variable "currency" {
  description = "Reporting currency."
  type        = string
  default     = "EUR"
}

variable "cpu" {
  description = "CPU reservation, MHz."
  type        = number
  default     = 500
}

variable "memory" {
  description = "Memory reservation, MB."
  type        = number
  default     = 384
}
