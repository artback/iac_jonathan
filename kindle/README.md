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

## Reinstalling KOReader (2026-08-25)

**Device: KindleBasic4 (Kindle 11th gen), firmware 5.18.4.0.1.**

Pick the build by ABI, not by guesswork. The device's interpreter is
`/lib/ld-linux-armhf.so.3`, so the correct asset is **`koreader-kindlehf`** —
`kindle`, `kindlepw2` and `kindle-legacy` all install without complaint and
then fail to launch, which looks exactly like a corrupt install. Confirm before
downloading:

```sh
file /Volumes/Kindle/koreader/luajit   # -> ld-linux-armhf.so.3
```

Install by extracting the zip **over** the existing directory. Do not wipe
`koreader/` first: the release zip contains neither `settings/` nor the
third-party plugins (`rssreader.koplugin`, `zen_ui.koplugin`), so a clean wipe
loses the theme, the reading progress and the RSS setup. Back both up anyway —
`~/Kindle-backups/`.

```sh
unzip -qo koreader-kindlehf-vX.Y.Z.zip -d /Volumes/Kindle
```

Verify against the manifest rather than eyeballing it; the file count *drops*
after a successful install, because overwriting each file also clears its
macOS `._` sidecar:

```sh
unzip -Z1 koreader-kindlehf-vX.Y.Z.zip | grep '^koreader/' | while read -r f; do
  [ -e "/Volumes/Kindle/$f" ] || echo "MISSING: $f"; done
dot_clean -m /Volumes/Kindle    # drop the sidecars entirely
```

Check the installed version in `koreader/version.log` before reinstalling. A
version with no matching GitHub release tag (e.g. v2026.07.2) is a **nightly**,
not a stable build, and is a fair suspect when something misbehaves.

## SSH onto the Kindle, without a cable

KOReader ships `SSH.koplugin` and a `dropbear` binary, so nothing needs
installing. Configured in `koreader/settings.reader.lua`:

```lua
["SSH_autostart"]         = true,    -- starts with KOReader
["SSH_key_only_auth"]     = true,    -- never accepts a password
["SSH_allow_no_password"] = false,
["SSH_port"]              = "2222",
```

Public keys go in `koreader/settings/SSH/authorized_keys`. Reach it over
Tailscale: `ssh -p 2222 root@100.98.255.112`.

Key-only is deliberate. The tailnet is the only network that can reach this
port, but a reader with a password-authenticated root shell on it is a bad
trade for the convenience.

**Caveat:** SSH lives inside KOReader, so it is up only while KOReader runs,
and the Kindle sleeps aggressively — it had been off the tailnet for a day when
this was written. Cable-free access is best-effort, not always-on.

## Start on boot — needs a shell, not the cable

Not doable over USB. Mass-storage mode exposes only the user partition
(`/mnt/us`): there is no `/etc` and no init system to add a job to. Autostart
has to be configured from a shell on the device, via SSH above or `kterm`
on-device.

## When plugins half-vanish: FAT32 fsck orphans

Symptom on 2026-08-25: KOReader started with the stock UI instead of Zen UI.
Nothing looked broken — the plugin directory was present, `plugins_disabled`
was empty, and KOReader itself exited cleanly. The log had the answer:

```
Error when loading plugins/zen_ui.koplugin/main.lua
  registry.lua:3: module '…/home/widgets/featured_custom' not found
```

The cause was **filesystem corruption, not KOReader**. `/mnt/us` is FAT32, and
an unclean disconnect leaves orphaned entries that the Kindle's boot-time fsck
renames to `FSCK####.REN`. Five plugin files across `zen_ui` and `rssreader`
had been renamed that way. Zen UI then failed one `require` and aborted its
whole init, which presents exactly as "the theme is gone".

Find them, and match each to its real name by content — the file's own
`id`/`require` lines identify it:

```sh
find /mnt/us -name 'FSCK*.REN'
```

Better, let the code say which names are missing rather than guessing:

```sh
cd /mnt/us/koreader/plugins
grep -rhoE 'require\("[^"]+"\)' <plugin> | sed 's/require("//;s/")//' | sort -u |
  while read m; do [ -f "<plugin>/$m.lua" ] || echo "MISSING: $m"; done
```

Two traps in that check. Plugin code also requires KOReader's *own* modules
(`common/json` resolves to `/mnt/us/koreader/common/json.lua`), so a "missing"
hit outside the plugin directory is usually a false alarm. And files loaded
from a table of paths rather than a literal `require` — Zen UI's
`modules/reader/patches/*` — won't show up; compare referenced names against
files on disk instead.

Recovered names, for reference:

| Orphan location | Real name |
| --- | --- |
| `zen_ui/…/home/widgets/` | `featured_custom.lua` |
| `zen_ui/common/quickstart/` | `quickstart_screen.lua` |
| `zen_ui/modules/reader/patches/` | `reader_footer.lua` |
| `rssreader.koplugin/` | `rssreader_newsblur.lua` |
| `rssreader.koplugin/sanitizers/` | `rssreader_sanitizer_fivefilters.lua` |

fsck also *created* `common/quickstart/` and moved `quickstart_pages.lua` into
it; the requires expect both files directly under `common/`. Verify each
restored file parses before restarting, using the device's own interpreter:

```sh
/mnt/us/koreader/luajit -e 'assert(loadfile("/path/to/file.lua"))'
```

**Eject properly.** This is the whole cause: yanking the cable, or letting the
Mac unmount uncleanly, is what orphans the files in the first place.

### Restarting KOReader over SSH — do not use `pkill -f reader.lua`

The pattern matches the shell running it, so the command kills its own SSH
session before any relaunch line executes, leaving KOReader stopped and the
device unreachable once it sleeps. Match on the binary instead, or restart
KOReader from the device.
