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

## ZenPM / ZenMTP / ZenFM (2026-08-25)

Three companions to Zen UI, all from xZenLabs, installed as KOReader plugins:

| Plugin | Version | What it is |
| --- | --- | --- |
| `zenpm.koplugin` | 1.4.1 | Package manager — install/update KOReader plugins on-device |
| `zen_mtp.koplugin` | 1.7.0 | Trigger MTP file-transfer mode |
| `zenfm.koplugin` | 1.0.1 | Web file manager, reachable from another device |

**Install the `-koreader-ereader-` release asset, not the Kindle standalone.**
ZenPM's standalone build is explicitly discouraged on jailbreaks that ship a
`JAILBREAK` booklet. This device is adbreak (`/mnt/us/adbreak.log`) and has no
such booklet, so the warning does not strictly apply — but the KOReader plugin
build avoids the question entirely and is the same software.

ZenPM and ZenFM ship both `-sf` and `-hf` backend binaries and pick at runtime,
so the armhf/soft-float trap that applies to KOReader itself does not apply
here.

Install over SSH rather than USB — that is the entire point of the exercise,
since mounting the volume is what orphaned files last time:

```sh
tar cf - zen_mtp.koplugin zenfm.koplugin zenpm.koplugin |
  ssh -p 2222 root@<kindle> 'cd /mnt/us/koreader/plugins && tar xf -'
```

**ZenMTP is the one that matters.** MTP does not hand the FAT32 filesystem to
the host, so the host cannot leave the volume dirty — which is what produced
the `FSCK*.REN` orphans documented above. Prefer it over mass storage.

**ZenFM's first login is `koreader123456789`.** Change it immediately in the
web UI; there is no config file to pre-seed it from, and the server binds to
every interface, so on this tailnet it is reachable from any node. Its own
dialog warns that plain HTTP sends the password in clear. The server does not
autostart, so it is inert until deliberately started.

### Restarting KOReader over SSH, safely

Establish a second path first — KOReader's dropbear dies with it:

```sh
/mnt/us/extensions/tailscale/bin/start_tailscaled_tun.sh   # then start_tailscale.sh
```

Then restart from a **script file**, never inline, so the kill pattern cannot
match the invoking shell's own command line:

```sh
printf '#!/bin/sh\nsleep 2\npkill -f reader.lua\nsleep 8\ncd /mnt/us/koreader\nexec ./koreader.sh --kual\n' \
  > /tmp/restart_ko.sh && chmod +x /tmp/restart_ko.sh
nohup setsid /tmp/restart_ko.sh >/tmp/ko_restart.log 2>&1 &
```
