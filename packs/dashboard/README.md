# Dashboard Nomad Pack

The homelab landing page at https://raspberrypi.tailb9a8bb.ts.net/ — a static
HTML page (nginx) with a hand-curated service list, routed to the root via Fabio.

## Editing the service list

1. Edit the `services` array in `files/dashboard.html`
2. Run `./update-html.sh` (re-embeds the HTML into the job template as base64)
3. `nomad-pack run packs/dashboard`

The base64 embedding is required: the page's JS uses `${...}` template
literals which HCL heredocs would try to interpolate.
