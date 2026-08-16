-- KOReader RSS Reader plugin — account configuration
-- https://github.com/omer-faruq/rssreader.koplugin
--
-- Lives at, on the device:
--     koreader/plugins/rssreader.koplugin/rssreader_configuration.lua
--
-- Kept in this repo because a Kindle factory reset wipes the device and this is
-- the only record of the setup. The api_key is deliberately absent: this path
-- is tracked and the repository is public. On the device it is the real key.
--
-- IMPORTANT: the plugin expects three top-level keys — accounts, sanitizers and
-- features — not a bare list of accounts. The installed copy is derived from the
-- plugin's own rssreader_configuration.sample.lua so that sanitizers/features
-- keep their shipped defaults; only the Miniflux entry is edited. Do the same
-- when rebuilding this rather than hand-writing a minimal file.
--
-- base_url is the Pi's tailnet IP over plain HTTP, deliberately, not the
-- Tailscale Serve HTTPS URL. Two reasons, both learned the hard way:
--
--   1. raspberrypi.tailb9a8bb.ts.net is a MagicDNS-only name — it resolves from
--      no public resolver. The Kindle cannot use MagicDNS because tailscaled
--      fails to rewrite /etc/resolv.conf there ("/etc" is read-only), so the
--      hostname never resolves and every request dies in getaddrinfo.
--   2. An IP cannot be used with the Serve endpoint either: the cert is issued
--      for the hostname, so TLS fails on SNI/CN.
--
-- Plain HTTP is not a downgrade here: the whole path runs inside WireGuard,
-- which already encrypts and authenticates it. TLS would be belt-and-braces.
-- The trade is that this only works while the Kindle is on the tailnet.

return {
    accounts = {
        {
            name = "Miniflux (homelab)",
            type = "miniflux",
            active = true,
            auth = {
                base_url = "http://100.116.81.88:8081",
                -- Miniflux → Settings → API Keys. The installed key is named
                -- "kindle-koreader" so a lost Kindle is one key revocation
                -- rather than an account password change.
                api_key = "PASTE_MINIFLUX_API_KEY_HERE",
            },
            options = {
                default_folder = nil,
            },
        },
        -- The sample ships further accounts (NewsBlur, CommaFeed, Fever,
        -- FreshRSS, two local). They are all active = false; note that the
        -- shipped "Sample" local account defaults to active = true, so it must
        -- be switched off or the reader opens with two accounts.
    },
    sanitizers = {},
    features = {},
}
