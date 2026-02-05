# Fabio Nomad Module

This module deploys Fabio, a fast, modern, zero-conf load balancing router for Nomad.

## Requirements

- A running Nomad cluster.
- Docker installed on the Nomad client nodes.

## Usage

To use this module, you need to have a Nomad cluster running. You can then run the job using the Nomad CLI.

**Important Note on `job_name`:** Nomad does not directly support variable interpolation in the `job "name"` block. If you need a truly dynamic job name, you would typically use an external templating tool (like `nomad pack`, `consul-template`, or a custom script) to generate the `.hcl` file before running `nomad run`. The `job_name` variable is provided for this purpose. If you are not using a templating tool, you will need to change `job "${var.job_name}"` to a static name, e.g., `job "fabio"`.

Here is an example of how to run the job with variables set:

```bash
nomad run fabio/fabio.hcl \
  -var "job_name=fabio-prod" \
  -var "datacenters=[\"dc1\", \"dc2\"]" \
  -var "lb_port=80" \
  -var "ui_port=8080" \
  -var "fabio_tags=[\"urlprefix-/foo\", \"urlprefix-/bar\"]"
```

Alternatively, you can create a `.tfvars` file with the variable values and use the `-var-file` flag:

```hcl
# fabio.tfvars
job_name = "fabio-prod"
datacenter = ["dc1", "dc2"]
lb_port = 80
ui_port = 8080
```

Then run the job with:
```bash
nomad run -var-file="fabio.tfvars" fabio/fabio.hcl
```

## Variables

This module uses the following variables:

- `job_name`: The name of the Nomad job. (Default: "fabio")
- `datacenters`: The datacenters where the job should run. (Default: ["dc1"])
- `type`: The type of job. (Default: "system")
- `group_name`: The name of the group within the job. (Default: "fabio")
- `lb_port`: The port for the load balancer. (Default: 9999)
- `ui_port`: The port for the UI. (Default: 9998)
- `image`: The Docker image to use. (Default: "fabiolb/fabio")
- `cpu`: The CPU resources to allocate. (Default: 200)
- `memory`: The memory resources to allocate. (Default: 128)
- `fabio_tags`: The tags for the Fabio service. (Default: ["urlprefix-/"])
