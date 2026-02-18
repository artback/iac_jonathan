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
  -var "count=3" \
  -var "image=httpd:2.4"
```

Alternatively, you can create a `.pkrvars.hcl` file with the variable values and use the `-var-file` flag:

```hcl
# webserver.pkrvars.hcl
count = 3
image = "httpd:2.4"
index_html = "<html><body><h1>Custom Content</h1></body></html>"
```

Then run the job with:
```bash
nomad run -var-file="webserver.pkrvars.hcl" webserver/webserver.hcl
```

## Variables

This module uses the following variables:

- `job_name`: The name of the job. (Default: "webserver")
- `datacenters`: The datacenters where the job should run. (Default: ["kalmar"])
- `count`: The number of instances to run. (Default: 3)
- `service_name`: The name of the service. (Default: "apache-webserver")
- `service_tags`: The tags for the service. (Default: ["urlprefix-/webserver"])
- `image`: The Docker image to use. (Default: "httpd:latest")
- `index_html`: The HTML content for index.html. (Default: "<html><body><h1>Hello World</h1></body></html>")
