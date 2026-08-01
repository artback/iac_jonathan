#!/usr/bin/env bash
# Moves the catalogue from the docker compose stack on this Mac to the Pi.
#
# Two things move: the PostGIS database, which is what the API serves, and the
# MinIO bucket, which is the durable record the database is derived from. Kafka
# holds nothing worth carrying — it is a transport, and its volume is empty.
#
# Run this only against a stack deployed with seed_mode = true. The enricher
# does not check whether a record has already been enriched, so with the bucket
# notification attached this mirror would queue a geocode per object: about
# 690,000 requests against a service that allows one a second. The script
# refuses to run if it finds the rule attached.
#
#   ./migrate-data.sh
#
# Environment (all optional except the passwords):
#   MUSEUM_REPO   path to the museum checkout        (default ~/Code/museum)
#   PI            the Pi's address                   (default 100.116.81.88)
#   PG_PASSWORD   museum database password on the Pi (required)
#   MINIO_PASSWORD  MinIO root password on the Pi    (required)
set -euo pipefail

REPO="${MUSEUM_REPO:-$HOME/Code/museum}"
PI="${PI:-100.116.81.88}"
PG_PORT="${PG_PORT:-55432}"
MINIO_PORT="${MINIO_PORT:-9100}"
PG_USER="${PG_USER:-museum}"
PG_DB="${PG_DB:-museum}"
BUCKET="${BUCKET:-museum}"
MINIO_USER="${MINIO_USER:-minioadmin}"
PG_IMAGE="${PG_IMAGE:-imresamu/postgis:16-3.4}"

: "${PG_PASSWORD:?set PG_PASSWORD to the pg_password from vars/museum-kalmar.pkrvars.hcl}"
: "${MINIO_PASSWORD:?set MINIO_PASSWORD to the minio_root_password from vars/museum-kalmar.pkrvars.hcl}"

# Local compose stack. These are the containers the data is coming out of.
LOCAL_PG="${LOCAL_PG:-museum-postgres}"
LOCAL_MINIO_CONTAINER="${LOCAL_MINIO_CONTAINER:-minio}"
LOCAL_MINIO_USER="${LOCAL_MINIO_USER:-minioadmin}"
LOCAL_MINIO_PASSWORD="${LOCAL_MINIO_PASSWORD:-minioadmin}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n=== %s ===\n' "$1"; }

# ---------------------------------------------------------------------------
say "Preflight"
# ---------------------------------------------------------------------------

docker inspect "$LOCAL_PG" >/dev/null 2>&1 ||
    { echo "Local container $LOCAL_PG is not running. Start the compose stack first." >&2; exit 1; }

nc -z -w5 "$PI" "$PG_PORT" ||
    { echo "Cannot reach $PI:$PG_PORT — is the museum job deployed?" >&2; exit 1; }
nc -z -w5 "$PI" "$MINIO_PORT" ||
    { echo "Cannot reach $PI:$MINIO_PORT — is the museum job deployed with enable_pipeline?" >&2; exit 1; }

# The check that protects the geocoder. An attached rule means this is not a
# seed_mode deploy, and mirroring would fire an event per object.
say "Checking the bucket notification is not attached"
RULES="$(docker run --rm --entrypoint sh minio/mc:latest -c "
    mc alias set pi 'http://$PI:$MINIO_PORT' '$MINIO_USER' '$MINIO_PASSWORD' >/dev/null 2>&1 || exit 0
    mc event ls pi/$BUCKET 2>/dev/null || true
")"
if printf '%s' "$RULES" | grep -q 'arn:minio:sqs'; then
    cat >&2 <<EOT
The bucket notification is still attached:

$RULES

Mirroring now would raise an ObjectCreated event for every one of the 345,000
objects, and the enricher re-geocodes unconditionally. Redeploy with
seed_mode = true first:

  nomad-pack run packs/museum -f vars/museum-kalmar.pkrvars.hcl --var seed_mode=true
EOT
    exit 1
fi
echo "No notification rule attached — safe to seed."

# ---------------------------------------------------------------------------
say "Dumping the catalogue from the compose stack"
# ---------------------------------------------------------------------------

DUMP="$WORK/museum.dump"
docker exec "$LOCAL_PG" pg_dump -U museum -d museum --format=custom --compress=9 > "$DUMP"
test -s "$DUMP"
echo "Dumped $(du -h "$DUMP" | cut -f1) to $DUMP"

# ---------------------------------------------------------------------------
say "Restoring into the Pi"
# ---------------------------------------------------------------------------

# The API is stopped for the restore. It applies its schema on every start, so
# leaving it connected means racing its CREATE TABLE against the restore's, and
# dropping the database out from under an open connection fails outright.
if command -v nomad >/dev/null 2>&1 && [ -n "${NOMAD_ADDR:-}" ]; then
    # Nomad refuses to scale a job while a deployment is in flight, with a 400.
    # Swallowing that error leaves the API running and the restore racing it,
    # so it is waited out rather than ignored.
    # nomad's output is captured whole and parsed afterwards, rather than piped
    # into an awk that exits early. Under "set -o pipefail" that early exit
    # closes the pipe, nomad dies of SIGPIPE, and the 141 takes the script with
    # it — mid-migration, which is the worst place to stop.
    echo "Waiting for any in-flight deployment to settle..."
    for _ in $(seq 60); do
        JOB_STATUS="$(nomad job status museum 2>/dev/null || true)"
        DEPLOY="$(printf '%s\n' "$JOB_STATUS" |
            sed -n '/Latest Deployment/,/^$/p' |
            sed -n 's/^Status *= *//p')"
        [ "$DEPLOY" != "running" ] && break
        sleep 5
    done

    echo "Scaling the API to zero for the restore..."
    nomad job scale museum api 0

    # The API task has a 10s shutdown_delay and a 30s kill_timeout, so it can
    # take the better part of a minute to actually let go of the database.
    # Waited for rather than slept through: a fixed sleep is a guess that gets
    # this wrong on a slow day.
    echo "Waiting for the API allocation to stop..."
    for _ in $(seq 60); do
        JOB_STATUS="$(nomad job status museum 2>/dev/null || true)"
        RUNNING="$(printf '%s\n' "$JOB_STATUS" |
            awk '$3 == "api" && $6 == "running" {n++} END {print n + 0}')"
        [ "$RUNNING" = "0" ] && break
        sleep 3
    done
    SCALE_BACK=1
else
    echo "nomad CLI or NOMAD_ADDR not available — stop the api group yourself before continuing." >&2
    read -r -p "Press enter once the api group is stopped: " _
    SCALE_BACK=0
fi

# Recreated rather than restored over. A --clean restore of a PostGIS database
# has to drop the extension the geography columns depend on, which is a far
# more delicate operation than simply starting from an empty database.
echo "Recreating the database..."
# WITH (FORCE) terminates any session still attached — the backup job, a psql
# left open, an API task slower to die than expected. Without it a single
# stray connection fails the drop, and -v ON_ERROR_STOP is what makes that
# failure stop the script rather than let it restore into the old database.
docker run --rm -e PGPASSWORD="$PG_PASSWORD" "$PG_IMAGE" \
    psql -v ON_ERROR_STOP=1 -h "$PI" -p "$PG_PORT" -U "$PG_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS $PG_DB WITH (FORCE);" \
    -c "CREATE DATABASE $PG_DB OWNER $PG_USER;"

echo "Restoring..."
docker run --rm -i -e PGPASSWORD="$PG_PASSWORD" -v "$WORK:/work:ro" "$PG_IMAGE" \
    pg_restore -h "$PI" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" \
    --no-owner --no-privileges --jobs 2 /work/museum.dump

echo "Row counts on the Pi:"
docker run --rm -e PGPASSWORD="$PG_PASSWORD" "$PG_IMAGE" \
    psql -h "$PI" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" \
    -c "SELECT 'museums' AS table, count(*) FROM museums
        UNION ALL SELECT 'exhibitions', count(*) FROM exhibitions
        UNION ALL SELECT 'places', count(*) FROM places;"

if [ "$SCALE_BACK" = "1" ]; then
    echo "Scaling the API back up..."
    nomad job scale museum api 1 || true
fi

# ---------------------------------------------------------------------------
say "Mirroring object storage"
# ---------------------------------------------------------------------------

# 345,000 objects, about 290 MiB.
#
# The mirror container joins the compose network and addresses MinIO by its
# container name. Going through the host's published port instead does not
# work here: host.docker.internal:9000 answers, but with a Go default-mux 404
# rather than the S3 API, so mc reports the bucket as missing and the whole
# transfer looks like a source problem it is not.
NETWORK="${COMPOSE_NETWORK:-$(docker inspect "$LOCAL_MINIO_CONTAINER" \
    --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null)}"
: "${NETWORK:?could not determine the compose network for $LOCAL_MINIO_CONTAINER}"
echo "Using docker network $NETWORK"

docker run --rm --network "$NETWORK" --entrypoint sh minio/mc:latest -c "
    set -e
    mc alias set src 'http://$LOCAL_MINIO_CONTAINER:9000' '$LOCAL_MINIO_USER' '$LOCAL_MINIO_PASSWORD'
    mc alias set pi  'http://$PI:$MINIO_PORT'             '$MINIO_USER'       '$MINIO_PASSWORD'
    mc mb --ignore-existing pi/$BUCKET
    # No --overwrite: plain mirror already copies anything new or changed, and
    # skips what matches. --overwrite re-uploads every object that is already
    # there, which turns resuming an interrupted 345,000-object transfer into
    # starting it again.
    mc mirror src/$BUCKET pi/$BUCKET
    echo
    echo 'Source:'; mc du src/$BUCKET
    echo 'Target:'; mc du pi/$BUCKET
"

cat <<EOT

=== Done ===

Both halves are across. Now turn the pipeline back on — redeploy without
seed_mode so the bucket notification is attached and the enricher starts:

  nomad-pack run packs/museum -f vars/museum-kalmar.pkrvars.hcl

Then check the API:

  curl -s "http://$PI:8091/v1/museums?place=Kyoto" | head -c 400
EOT
