-- KOReader RSS Reader plugin — account configuration
-- https://github.com/omer-faruq/rssreader.koplugin
--
-- Copy to the Kindle at:
--     koreader/plugins/rssreader.koplugin/rssreader_configuration.lua
--
-- Kept in this repo because a Kindle factory reset wipes the device and this
-- is the only place the account setup exists. The API key is deliberately NOT
-- stored here — vars/ is gitignored but this file is not, and the key lives in
-- plaintext on the device regardless. Paste it on the Kindle after copying.
--
-- base_url is the Tailscale Serve URL, which is also miniflux's own BASE_URL,
-- so it is correct whether the Kindle reaches the Pi over the tailnet or over
-- Tailscale Funnel — the hostname and port do not change between the two.

return {
    {
        name = "Miniflux",
        type = "miniflux",
        active = true,
        auth = {
            base_url = "https://raspberrypi.tailb9a8bb.ts.net:10000",
            -- Miniflux → Settings → API Keys → Create a new API key.
            -- This grants full access to the account; rotate it there if the
            -- Kindle is ever lost, rather than changing the account password.
            api_key = "PASTE_MINIFLUX_API_KEY_HERE",
        },
        options = {
            default_folder = nil,
        },
    },
}
