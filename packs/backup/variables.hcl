variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "cron" {
  description = "Backup schedule (UTC)."
  type        = string
  default     = "0 3 * * *"
}

variable "pg_user" {
  description = "The postgres superuser for pg_dumpall."
  type        = string
  default     = "postgres"
}

variable "local_backup_dir" {
  description = "Backup destination on the NVMe (same disk as the data — first copy)."
  type        = string
  default     = "/home/dwight/backups"
}

variable "usb_backup_dir" {
  description = "Backup destination on the USB drive (separate physical disk — second copy)."
  type        = string
  default     = "/mnt/usbdrive/backups"
}

variable "app_state_paths" {
  description = "Host paths of docker volume data to include in the app-state tarball, as name=path."
  type        = map(string)
  default = {
    n8n             = "/var/lib/docker/volumes/n8n_data/_data"
    mealie          = "/var/lib/docker/volumes/mealie_data/_data"
    beszel          = "/var/lib/docker/volumes/beszel_vol/_data"
    changedetection = "/var/lib/docker/volumes/datastore-volume/_data"
    convertx        = "/home/dwight/convertx"
    searxng         = "/var/lib/docker/volumes/searxng_data/_data"
    abs-config      = "/var/lib/docker/volumes/abs_config/_data"
    abs-metadata    = "/var/lib/docker/volumes/abs_metadata/_data"
    printbot        = "/var/lib/docker/volumes/printbot_data/_data"
    mailbot         = "/var/lib/docker/volumes/mailbot_data/_data"
  }
}
