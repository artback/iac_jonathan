job "stock-bot" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "bot" {
    count = 1

    # Outbound only: long-polls Telegram and reads a price API. No ports, no
    # service registration, nothing for Fabio or Consul to route.
    restart {
      attempts = 3
      interval = "10m"
      delay    = "30s"
      mode     = "delay"
    }

    task "bot" {
      driver = "docker"

      config {
        image   = "[[ var "image" . ]]"
        command = "/bin/sh"
        args    = ["-c", "/local/start.sh"]
      }

      env {
        HOME                 = "/data"
        PIP_ROOT_USER_ACTION = "ignore"
        STOCK_PRICE_CONFIG   = "/local/stock.yaml"
      }

      # Secrets come from Nomad Variables, never from the job spec:
      #   nomad var put nomad/jobs/stock-bot telegram_token=... allowed_chat_ids=... twelvedata_api_key=...
      # This job was the first here to use that pattern; the rest of the packs
      # were migrated to match it.
      template {
        destination = "secrets/bot.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{ with nomadVar "nomad/jobs/stock-bot" }}
TELEGRAM_TOKEN={{ .telegram_token }}
TELEGRAM_ALLOWED_CHAT_IDS={{ index . "allowed_chat_ids" }}
TWELVEDATA_API_KEY={{ index . "twelvedata_api_key" }}
{{ end }}
EOH
      }

      # Holdings are private. They are rendered from the gitignored vars file,
      # so the portfolio never reaches this public repository.
      template {
        destination = "local/stock.yaml"
        change_mode = "restart"
        data        = <<EOH
holdings:
[[ range $ticker, $shares := var "holdings" . ]]  [[ $ticker ]]: [[ $shares ]]
[[ end ]]currency: [[ var "currency" . ]]
EOH
      }

      template {
        destination = "local/start.sh"
        change_mode = "restart"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -eu
# Installed from the release tarball rather than git+https: the slim
# image has no git, and a tarball avoids installing one just to fetch
# a few files. Pinned to a tag so an unattended restart can't pull an
# untested main.
pip install --no-cache-dir --quiet \
  "https://github.com/artback/stock-change/archive/refs/tags/[[ var "stock_change_version" . ]].tar.gz"
exec stock-price-bot
EOH
      }

      resources {
        cpu    = [[ var "cpu" . ]]
        memory = [[ var "memory" . ]]
      }
    }
  }
}
