# n8n Nomad Module

This module deploys n8n, a free and open fair-code licensed workflow automation tool.

## Requirements

- A running Nomad cluster.
- Docker installed on the Nomad client nodes.

## Usage

To use this module, you need to have a Nomad cluster running. You can then run the job using the Nomad CLI.

Here is an example of how to run the job with variables set for a PostgreSQL database:

```bash
nomad run n8n/n8n.hcl \
  -var "port=8080" \
  -var "n8n_tags=[\"urlprefix-/myn8n\"]" \
  -var "host_volume_name=/mnt/n8n_storage" \
  -var "db_postgresdb_database=n8n" \
  -var "db_postgresdb_host=your_postgres_host" \
  -var "db_postgresdb_port=5432" \
  -var "db_postgresdb_user=n8n_user" \
  -var "db_postgresdb_schema=public" \
  -var "db_postgresdb_password=your_password"
```

Alternatively, you can create a `.tfvars` file with the variable values and use the `-var-file` flag:

```hcl
# n8n.tfvars
port = 8080
n8n_tags = ["urlprefix-/myn8n"]
host_volume_name = "/mnt/n8n_storage"
db_postgresdb_database = "n8n"
db_postgresdb_host = "your_postgres_host"
db_postgresdb_port = 5432
db_postgresdb_user = "n8n_user"
db_postgresdb_schema = "public"
db_postgresdb_password = "your_password"
```

Then run the job with:
```bash
nomad run -var-file="n8n.tfvars" n8n/n8n.hcl
```

## Variables

This module uses the following variables:

- `datacenters`: The datacenters where the job should run. (Default: ["dc1"])
- `count`: The number of instances to run. (Default: 1)
- `port`: The port for n8n. (Default: 5678)
- `image`: The Docker image to use. (Default: "docker.n8n.io/n8nio/n8n")
- `cpu`: The CPU resources to allocate. (Default: 500)
- `memory`: The memory resources to allocate. (Default: 512)
- `n8n_tags`: The tags for the n8n service for Fabio routing. (Default: ["urlprefix-/n8n"])
- `volume_id`: The ID of the host volume to use for data persistence. (Default: "n8n_data")
- `host_volume_name`: The name of the host volume on the Nomad client. This is the path to the directory on the host machine where the data will be stored. (Default: "/opt/n8n-data")
- `generic_timezone`: The generic timezone for n8n. (Default: "Europe/Berlin")
- `tz`: The timezone for n8n. (Default: "Europe/Berlin")
- `n8n_enforce_settings_file_permissions`: Enforce settings file permissions. (Default: true)
- `n8n_runners_enabled`: Enable n8n runners. (Default: true)
- `db_type`: The type of database to use. (Default: "postgresdb")
- `db_postgresdb_database`: The PostgreSQL database name.
- `db_postgresdb_host`: The PostgreSQL host.
- `db_postgresdb_port`: The PostgreSQL port.
- `db_postgresdb_user`: The PostgreSQL user.
- `db_postgresdb_schema`: The PostgreSQL schema.
- `db_postgresdb_password`: The PostgreSQL password.

## Connecting to the PostgreSQL Module

If you are running the `postgres` module from this project, you can connect this `n8n` module to it using Nomad's service discovery.

First, ensure the `postgres` job is running. Then, when you run the `n8n` job, you can use the following variables to connect to the `postgres` service:

- `db_postgresdb_host`: `"postgres.service.consul"`
- `db_postgresdb_port`: `5432` (or the value of `db_port` in your `postgres` job)
- `db_postgresdb_user`: The value of `pg_user` in your `postgres` job.
- `db_postgresdb_password`: The value of `pg_password` in your `postgres` job.
- `db_postgresdb_database`: The value of `pg_db_name` in your `postgres` job.
- `db_postgresdb_schema`: `public` (usually)

### Example

1.  **Run the `postgres` job:**
    ```bash
    nomad run postgres/postgres.hcl \
      -var "pg_user=n8n" \
      -var "pg_password=a_strong_password" \
      -var "pg_db_name=n8n"
    ```

2.  **Run the `n8n` job:**
    ```bash
    nomad run n8n/n8n.hcl \
      -var "db_postgresdb_host=postgres.service.consul" \
      -var "db_postgresdb_user=n8n" \
      -var "db_postgresdb_password=a_strong_password" \
      -var "db_postgresdb_database=n8n"
    ```

