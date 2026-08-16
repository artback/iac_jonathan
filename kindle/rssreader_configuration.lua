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
-- base_url is the Tailscale Serve URL, which is also miniflux's own BASE_URL, so
-- it is correct over the tailnet and would stay correct behind Tailscale Funnel.
-- Reaching it requires the Kindle to be on the tailnet — see README.md.

return {
    accounts = {
        {
            name = "Miniflux (homelab)",
            type = "miniflux",
            active = true,
            auth = {
                base_url = "https://raspberrypi.tailb9a8bb.ts.net:10000",
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
