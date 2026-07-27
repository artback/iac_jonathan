variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "abs_version" {
  description = "The Audiobookshelf version to run. Pin this — do not use latest."
  type        = string
  default     = "2.35.1"
}

variable "config_volume" {
  description = "The docker named volume for /config (users, progress, settings)."
  type        = string
  default     = "abs_config"
}

variable "metadata_volume" {
  description = "The docker named volume for /metadata (covers, cache)."
  type        = string
  default     = "abs_metadata"
}

variable "audiobooks_dir" {
  description = "Host directory with the audiobook library (on the USB drive)."
  type        = string
  default     = "/mnt/usbdrive/audiobooks"
}

variable "podcasts_dir" {
  description = "Host directory for downloaded podcasts (on the USB drive)."
  type        = string
  default     = "/mnt/usbdrive/podcasts"
}

variable "service_tags" {
  description = "The tags for the audiobookshelf service."
  type        = list(string)
  default     = ["audiobookshelf"]
}
