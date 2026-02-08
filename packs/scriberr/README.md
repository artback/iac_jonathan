# Scriberr Nomad Pack

This pack deploys Scriberr, an AI Transcription service, on Nomad.

## Variables

- `datacenters` - The datacenters where the job should run.
- `scriberr_version` - The version of Scriberr to run.
- `service_tags` - The tags for the scriberr service.
- `scriberr_data_volume` - The name of the docker volume for scriberr data.
- `env_data_volume` - The name of the docker volume for whisperx-env data.
- `puid` - PUID for the scriberr process.
- `pgid` - PGID for the scriberr process.
