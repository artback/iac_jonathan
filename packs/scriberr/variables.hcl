variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "domain" {
  description = "The root domain for the application (e.g., example.com)."
  type        = string
  default     = "localhost"
}

variable "scriberr_version" {
  description = "The version of Scriberr to run."
  type        = string
  default     = "v1.2.0"
}

variable "service_tags" {
  description = "The tags for the scriberr service."
  type        = list(string)
  default     = ["urlprefix-scriberr.localhost/"]
}

variable "scriberr_data_volume" {
  description = "The name of the docker volume for scriberr data."
  type        = string
  default     = "scriberr_data"
}

variable "env_data_volume" {
  description = "The name of the docker volume for whisperx-env data."
  type        = string
  default     = "env_data"
}

variable "puid" {
  description = "PUID for the scriberr process."
  type        = string
  default     = "1000"
}

variable "pgid" {
  description = "PGID for the scriberr process."
  type        = string
  default     = "1000"
}

variable "allowed_origins" {
  description = "Comma-separated list of allowed origins for production."
  type        = string
  default     = ""
}

variable "secure_cookies" {
  description = "Whether to use secure cookies. Set to false if not using SSL."
  type        = bool
  default     = true
}

variable "enable_diarization" {
  description = "Whether to enable speaker diarization (Smart Speaker Detection). Requires HuggingFace token if true."
  type        = bool
  default     = false
}

variable "huggingface_access_token" {
  description = "HuggingFace access token for PyAnnote diarization."
  type        = string
  default     = ""
}

variable "enable_canary" {
  description = "Whether to enable NVIDIA Canary model."
  type        = bool
  default     = false
}

variable "enable_parakeet" {
  description = "Whether to enable NVIDIA Parakeet model."
  type        = bool
  default     = false
}
