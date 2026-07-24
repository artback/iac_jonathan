variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "selenium_image" {
  description = "Selenium image, digest-pinned (official multi-arch build proven on arm64)."
  type        = string
  default     = "selenium/standalone-chromium@sha256:3400b92f1cddb2dfaaf358654e8f7d83d7be45192fb73c5f28c25faa28d36504"
}

variable "max_sessions" {
  description = "Max concurrent browser sessions."
  type        = number
  default     = 2
}

variable "session_timeout" {
  description = "Session timeout in seconds."
  type        = number
  default     = 300
}
