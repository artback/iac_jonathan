# Museum

The museum catalogue — about 180,000 museums, the exhibitions currently on
show, and the pipeline that maintains both — running on the Pi.

Source: [artback/museumscraper](https://github.com/artback/museumscraper).

## What this deploys

Four job files render from this pack:

| Job | Type | What it is |
|---|---|---|
| `museum` | service | PostGIS, MinIO, Kafka, the HTTP API, the enricher |
| `museum-refresh` | periodic | Rescrapes exhibition listings, daily |
| `museum-backup` | periodic | Dumps the catalogue to NVMe and USB, daily |
| `museum-crawl` | periodic | Rebuilds from Wikidata/Wikipedia/OSM, weekly — off by default |

Everything is the same image and the same binary; the groups differ only in the
subcommand they start it with.

## Volumes must be mount stanzas

The three stateful tasks use `mount { type = "volume" }` rather than an entry
in the docker driver's `volumes` list. This is not a style preference.

A `volumes` entry whose source is not an absolute path — `"museum-postgres-data:/var/lib/postgresql/data"` —
is resolved by the driver **against the allocation directory**, not as a Docker
named volume. It becomes `/opt/nomad/data/alloc/<id>/<task>/museum-postgres-data`,
which survives task restarts and redeploys that reuse the allocation, and is
destroyed the moment a deploy places a new one. The catalogue verified as
present for an hour before the first CD run replaced the allocations and took
180,137 museums and 345,128 objects with it.

Counting rows does not test this. The test is: write a row, `nomad alloc stop`
the group, read it back from the replacement allocation. `docker volume ls` on
the client should list the volume by name; if it does not, the data is
somewhere temporary.

## Two things that are not obvious

**PostGIS must not be `postgis/postgis`.** That repository publishes amd64
only, and the client is a Raspberry Pi — the image will not run. `pg_image`
defaults to `imresamu/postgis`, the multi-arch build of the same Dockerfile
maintained by a docker-postgis maintainer.

**Seeding must not raise bucket events.** The enricher does not check whether a
record has already been enriched: it geocodes every museum an event names, and
then makes a second Nominatim call for the place details. Mirroring the existing
345,000 objects into a bucket with the notification rule attached would queue
roughly 690,000 requests against a geocoder that allows one per second — about
eight days of traffic, against a usage policy that forbids bulk geocoding.
`seed_mode = true` detaches the rule and runs the enricher at zero instances so
the initial load lands quietly. `migrate-data.sh` refuses to run without it.

## Ports

Chosen around what the Pi already has: `8090` is beszel, `9000` is mealie,
`5432` is the shared postgres, and `9100` is node-exporter.

That last one is worth remembering. node-exporter and prometheus run on the
cluster but have no packs in this repository, so grepping the job files for
`static =` does not find their ports. MinIO was briefly given 9100, which put
node-exporter into a restart loop and blinded Prometheus to every host metric.
Check `nomad node status -verbose` or the dashboard's service list — not just
this repository — before claiming a port.

| Service | Host port |
|---|---|
| API | 8091 |
| PostGIS | 55432 |
| MinIO S3 | 9110 |
| MinIO console | 9111 |
| Kafka | 29092 |

## Routing

fabio routes `/map` and `/v1` to the API unstripped, so the map is at
<http://100.116.81.88/map>. A single `urlprefix-/museum strip=/museum` would
be the tidier tag and does not work: the map page requests `/v1/...` and
`/map/vendor/...` as absolute paths, which would miss the prefix entirely and
fall through to the dashboard on `/`. Both tags are longer than the
dashboard's `urlprefix-/`, and fabio matches the longest prefix, so nothing
about the dashboard had to change.

## Why a second Postgres

The shared `postgres` job runs `postgres:18-alpine`. The catalogue's radius
queries need PostGIS and its similarity search needs pg_trgm, and that image has
neither. It also means the shared `backup` job — which runs `pg_dumpall` against
the shared instance — never sees this database, which is why this pack brings
its own `museum-backup`.

## First deployment

Build and push the image for arm64:

```bash
./scripts/publish-image.sh 0.1.0 ~/Code/museum
```

Set the resulting tag and real passwords in `vars/museum-kalmar.pkrvars.hcl`,
then deploy in seed mode:

```bash
nomad-pack run packs/museum -f vars/museum-kalmar.pkrvars.hcl --var seed_mode=true
```

Move the data across — the database and the object storage both:

```bash
PG_PASSWORD=... MINIO_PASSWORD=... ./scripts/migrate-data.sh
```

Then redeploy without seed mode, which attaches the bucket notification and
starts the enricher:

```bash
nomad-pack run packs/museum -f vars/museum-kalmar.pkrvars.hcl
```

Check it:

```bash
curl -s "http://100.116.81.88:8091/v1/museums?place=Kyoto" | head -c 400
```

The map is at `http://100.116.81.88:8091/map`.

## Capacity

The Pi has 8 GiB, of which about 4 GiB was already reserved by the other
sixteen allocations. The full stack reserves roughly 2.75 GiB:

| Group | Reserved | Max |
|---|---|---|
| db (PostGIS) | 768 MiB | 1536 MiB |
| broker (Kafka) | 1024 MiB | 1536 MiB |
| storage (MinIO) | 512 MiB | 1024 MiB |
| api | 256 MiB | 512 MiB |
| enricher | 256 MiB | 512 MiB |

Kafka's JVM is capped by `kafka_heap` — left alone it sizes its heap from total
system memory and takes considerably more than the job is allowed.

If that is too tight, `enable_pipeline = false` deploys only PostGIS and the
API. The catalogue is still served in full; it just can no longer be crawled or
enriched on the Pi, and would be updated by restoring a dump taken elsewhere.
That saves about 1.8 GiB.

## Variables

See `variables.hcl` — every variable carries its own description. The ones worth
knowing about:

- `seed_mode` — read the section above before setting it false for the first load
- `enable_pipeline` — MinIO, Kafka and the enricher, or just PostGIS and the API
- `enable_crawl` — registers the weekly crawl; off because it saturates the Pi for hours
- `image` — must be linux/arm64
- `pg_password`, `minio_root_password` — no defaults, set them in the vars file
