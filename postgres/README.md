# PostgreSQL Nomad Module

This module deploys a single-node PostgreSQL instance in a Docker container as a Nomad job. This setup is intended for development or small-scale production environments. It is not a clustered or highly available setup.

## Requirements

- A running Nomad cluster.
- Docker installed on the Nomad client nodes.
- A pre-existing directory on the Nomad client node to be used as a host volume for data persistence.

## Storage

This module uses a Nomad "host volume" for data persistence. This means that the PostgreSQL data will be stored in a directory on the Nomad client node where the container is running. You must specify the path to this directory in the `host_volume_name` variable.

**Important:** Since the data is stored on a specific client node, if the job is rescheduled to a different node, it will lose access to the data. For production environments, consider using a distributed storage solution like Ceph or a cloud provider's block storage.

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
- `host_volume_name`: The name of the host volume on the Nomad client. This is the path to the directory on the host machine where the data will be stored.
- `db_port`: The port to expose for the database.
- `pg_version`: The version of PostgreSQL to use.
- `pg_password`: The password for the PostgreSQL database.
- `pg_db_name`: The name of the PostgreSQL database.

**Note:** It is recommended to use Nomad's built-in secrets management or HashiCorp Vault to manage the `pg_password` variable in a production environment.
