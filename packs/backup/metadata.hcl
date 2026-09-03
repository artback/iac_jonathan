pack {
  name = "backup"
  description = "Nightly backup: postgres dumps + app state (mealie, beszel, and friends) to NVMe and USB"
  version = "0.0.1"
}

app {
  url = "https://www.postgresql.org/docs/current/app-pg-dumpall.html"
}
