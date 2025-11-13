# Webserver Nomad Module

This module deploys an Apache webserver as a Nomad job.

## Requirements

- A running Nomad cluster.
- Docker installed on the Nomad client nodes.

## Usage

To use this module, you need to have a Nomad cluster running. You can then run the job using the Nomad CLI.

Here is an example of how to run the job with variables set:

```bash
nomad run webserver/webserver.hcl \
  -var "count=5" \
  -var "http_port=8080" \
  -var "image=httpd:2.4"
```

Alternatively, you can create a `.tfvars` file with the variable values and use the `-var-file` flag:

```hcl
# webserver.tfvars
count = 5
http_port = 8080
image = "httpd:2.4"
```

Then run the job with:
```bash
nomad run -var-file="webserver.tfvars" webserver/webserver.hcl
```

## Variables

This module uses the following variables:

- `datacenters`: The datacenters where the job should run. (Default: ["dc1"])
- `type`: The type of job. (Default: "service")
- `count`: The number of instances to run. (Default: 3)
- `http_port`: The port for HTTP traffic. (Default: 80)
- `service_name`: The name of the service. (Default: "apache-webserver")
- `service_tags`: The tags for the service. (Default: ["urlprefix-/"])
- `check_name`: The name of the health check. (Default: "alive")
- `check_type`: The type of the health check. (Default: "http")
- `check_path`: The path for the health check. (Default: "/")
- `check_interval`: The interval for the health check. (Default: "10s")
- `check_timeout`: The timeout for the health check. (Default: "2s")
- `restart_attempts`: The number of restart attempts. (Default: 2)
- `restart_interval`: The interval for restart attempts. (Default: "30m")
- `restart_delay`: The delay between restart attempts. (Default: "15s")
- `restart_mode`: The restart mode. (Default: "fail")
- `image`: The Docker image to use. (Default: "httpd:latest")
