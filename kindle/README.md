# Kindle (KOReader) configuration

Device-side config for the Kindle. Nothing here is deployed by Nomad — these
files are copied onto the device, and live in this repo because a Kindle
factory reset wipes them and there is no other copy.

## RSS reader

[`rssreader.koplugin`](https://github.com/omer-faruq/rssreader.koplugin) reads
the miniflux instance on the Pi directly, so articles sync with the same read
state as the web UI rather than being a second, separate feed list.

Install from the device with
[`appstore.koplugin`](https://github.com/omer-faruq/appstore.koplugin) — no USB
cable needed — then copy `rssreader_configuration.lua` to:

```
koreader/plugins/rssreader.koplugin/rssreader_configuration.lua
```

and paste the API key from **miniflux → Settings → API Keys**. The key is not
stored in this repo; it grants full access to the account, so if the Kindle is
lost, revoke that key rather than changing the password.

## Reaching miniflux from outside the house

The Kindle is rarely on the same LAN as the Pi, so something has to bridge the
gap. **The chosen answer is to put the Kindle on the tailnet**, which needs no
server-side change at all: miniflux stays tailnet-only, UFW is untouched,
nothing becomes publicly reachable, and the `base_url` above already resolves.

Tailscale on a jailbroken Kindle is a community KUAL extension, written up by
Tailscale at <https://tailscale.com/blog/tailscale-jailbroken-kindle>. It needs
the jailbreak that KOReader already implies, plus KUAL/MRPI and USBNetworking,
and the **arm** (not arm64) static binaries. Start is manual — *Start
Tailscaled*, wait ~10s, then *Start Tailscale* — so after a reboot the tailnet
comes up only once you launch it from KUAL. Expect to re-check it after any
firmware change; OTA updates must stay disabled or the jailbreak goes with them.

The fallback, if that proves too fragile in practice, is `tailscale funnel
10000 on` on the Pi, which publishes miniflux on the open internet behind its
own login — the same trade already accepted for Calibre-Web, which the Kindle
reaches at a public HTTPS URL on the seedbox. Because Funnel reuses the exact
hostname and port already in `base_url`, switching to it is a one-line change on
the Pi and **no change at all** on the device.
