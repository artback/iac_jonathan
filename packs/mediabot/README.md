# Mediabot Nomad Pack

Telegram bot for the seedbox Radarr/Sonarr — search and **add** movies/series
from chat, not just receive download updates. Outbound long-polling only;
nothing exposed. Coexists with Radarr/Sonarr's own Telegram notifications on
the same bot token (they only send; this bot polls).

## Commands

- `/movie TITLE` — search Radarr, tap an inline button to add
- `/series TITLE` — same for Sonarr
- bare text — searches both
- `/queue` — active downloads with progress
- `/upcoming` — releases in the next 7 days

Adds use the instance's **first quality profile and root folder** and trigger
an immediate release search. Already-added items are marked and not offered.

## Setup

Secrets live in gitignored `vars/mediabot.hcl`:

```hcl
telegram_token   = "..."   # @BotFather token for the bot
allowed_chat_ids = "..."   # comma-separated
radarr_api_key   = "..."   # Radarr → Settings → General
sonarr_api_key   = "..."   # Sonarr → Settings → General
```

Deploy: `nomad-pack run packs/mediabot -f vars/mediabot.hcl`
