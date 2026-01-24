# Mealie on Nomad

Mealie is a self-hosted recipe manager and meal planner.

## Configuration

The job is configured via the `mealie.hcl` file. You can override the default variables when running the job.

### Variables

| Variable | Description | Default |
| :--- | :--- | :--- |
| `datacenters` | List of datacenters to run in. | `["kalmar"]` |
| `domain` | The root domain (used for BASE_URL). | `localhost` |
| `mealie_version` | Docker tag version. | `latest` |
| `pg_root_user` | Root user for Postgres. | `postgres` |
| `db_postgresdb_root_password` | **Required**. Root password for DB init. | - |
| `db_postgresdb_user` | Database user for Mealie. | `mealie` |
| `db_postgresdb_password` | **Required**. Password for Mealie DB user. | - |
| `db_postgresdb_database` | Database name for Mealie. | `mealie` |
| `service_tags` | List of tags for Consul/Fabio. | `["urlprefix-mealie.localhost/"]` |

## Usage

### 1. Run with Nomad CLI

```bash
nomad job run \
  -var="db_postgresdb_root_password=supersecret" \
  -var="db_postgresdb_password=mealiepass" \
  -var='service_tags=["urlprefix-recipes.example.com/"]' \
  mealie.hcl
```

### 2. Deploy via Ansible

Add the variables to your inventory or pass them as extra vars:

```bash
ansible-playbook playbooks/site.yml --tags mealie \
  --extra-vars '{"postgres_root_password": "root", "mealie_db_password": "pass", "mealie_service_tags": ["urlprefix-recipes.local/"]}'
```