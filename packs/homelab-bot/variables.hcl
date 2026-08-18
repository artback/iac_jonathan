variable "datacenters" {
  description = "The datacenters where the job should run."
  type        = list(string)
  default     = ["kalmar"]
}

variable "image" {
  description = "Base image."
  type        = string
  default     = "python:3.12-alpine"
}

variable "allowed_chat_ids" {
  description = "Comma-separated Telegram chat IDs permitted to talk to the bot."
  type        = string
  default     = "485643205"
}

variable "certs_dir" {
  description = "Host directory of world-readable client certs. The originals under /etc/certs/nomad are 0640 root:nomad and unreadable inside a container, so the tls role keeps copies here — same trick the prometheus pack uses."
  type        = string
  default     = "/etc/certs/prometheus"
}

variable "backup_dir" {
  description = "Postgres dump directory, mounted read-only so /backup can report freshness."
  type        = string
  default     = "/home/dwight/backups/postgres"
}

variable "nomad_addr" {
  description = "Nomad API address."
  type        = string
  default     = "https://100.116.81.88:4646"
}

variable "prometheus_url" {
  description = "Prometheus base URL, used for host CPU/memory/disk rather than mounting /proc."
  type        = string
  default     = "http://100.116.81.88:9090/prometheus"
}

variable "cpu" {
  description = "CPU reservation, MHz."
  type        = number
  default     = 100
}

variable "memory" {
  description = "Memory reservation, MB."
  type        = number
  default     = 64
}
