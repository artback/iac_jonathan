# PostgreSQL Nomad Module

This module deploys a PostgreSQL container as a Nomad job.

## Usage

To use this module, you need to have a Nomad cluster running. You can then run the job using the Nomad CLI:

```bash
nomad run postgres/postgres.hcl
```

## Variables

This module uses the following variables:

- `job_name`: The name of the Nomad job.
- `datacenter`: The datacenter where the job should run.
- `group_name`: The name of the group within the job.
- `volume_id`: The ID of the host volume to use for data persistence.
- `host_volume_name`: The name of the host volume on the Nomad client.
- `db_port`: The port to expose for the database.
- `pg_version`: The version of PostgreSQL to use.
- `pg_password`: The password for the PostgreSQL database.
- `pg_db_name`: The name of the PostgreSQL database.

**Note:** It is recommended to use Nomad's built-in secrets management or HashiCorp Vault to manage the `pg_password` variable in a production environment.
