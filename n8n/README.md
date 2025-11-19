# n8n Nomad Module

This module deploys n8n, a free and open fair-code licensed workflow automation tool.

## Requirements

- A running Nomad cluster.
- Docker installed on the Nomad client nodes.

## Usage

To use this module, you need to have a Nomad cluster running. You can then run the job using the Nomad CLI.

Here is an example of how to run the job with variables set:

```bash
nomad run n8n/n8n.hcl \
  -var "port=8080" \
  -var "n8n_tags=[\"urlprefix-/myn8n\"]"
```

Alternatively, you can create a `.tfvars` file with the variable values and use the `-var-file` flag:

```hcl
# n8n.tfvars
port = 8080
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

