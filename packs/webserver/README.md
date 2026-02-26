# Webserver Nomad Pack

This pack deploys a webserver (Apache or Nginx) as a Nomad job. It allows for easy customization of the image and the content of the `index.html` file.

## Requirements

- A running Nomad cluster.
- Docker installed on the Nomad client nodes.

## Usage

You can run this pack using the Nomad CLI. By default, it uses Apache (`httpd`).

### Running with Apache (Default)

```bash
nomad pack run webserver
```

### Running with Nginx

To use Nginx, you need to override the `image` and `target_path` variables:

```bash
nomad pack run webserver \
  -var="image=nginx:alpine" \
  -var="target_path=/usr/share/nginx/html/index.html"
```

### Using a Variable File

You can also use a `.hcl` file for configurations:

```hcl
# nginx.vars.hcl
image       = "nginx:alpine"
target_path = "/usr/share/nginx/html/index.html"
index_html  = "<html><body><h1>Hello from Nginx</h1></body></html>"
```

Then run with:
```bash
nomad pack run -var-file=nginx.vars.hcl webserver
```

## Variables

- `job_name`: The name of the job. (Default: `"webserver"`)
- `datacenters`: The datacenters where the job should run. (Default: `["kalmar"]`)
- `count`: The number of instances to run. (Default: `3`)
- `image`: The Docker image to use. (Default: `"httpd:latest"`)
- `index_html`: The HTML content for index.html. (Default: `"<html><body><h1>Hello World</h1></body></html>"`)
- `target_path`: The target path for `index.html` inside the container. 
    - Apache: `/usr/local/apache2/htdocs/index.html` (Default)
    - Nginx: `/usr/share/nginx/html/index.html`
- `service_name`: The name of the service in Consul. (Default: `"webserver"`)
- `service_tags`: The tags for the service. (Default: `["urlprefix-/webserver strip=/webserver"]`)
