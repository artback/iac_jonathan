# Ansible Configuration for Nomad & Consul Cluster

This directory contains Ansible roles and playbooks to provision and configure a Nomad and Consul cluster, secured via Tailscale.

## Roles

| Role | Description |
| :--- | :--- |
| `common` | Installs common dependencies (Docker, curl, unzip). |
| `tailscale` | Installs and authenticates Tailscale. |
| `consul` | Installs and configures Consul (Server/Client). |
| `nomad` | Installs and configures Nomad (Server/Client) and the Docker plugin. |
| `fabio` | Deploys the Fabio load balancer as a Nomad job. |

## Configuration & Variables

The setup is highly configurable via variables defined in `roles/<role_name>/defaults/main.yml`. You can override these in your inventory or playbook `vars`.

### Network & Interfaces (Crucial)
By default, the configuration assumes you are using **Tailscale**.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `consul_bind_interface` | `tailscale0` | Interface Consul binds to (uses `GetInterfaceIP`). |
| `nomad_bind_interface` | `tailscale0` | Interface Nomad uses for advertising (RPC, Serf, HTTP). |
| `nomad_network_interface` | `tailscale0` | Interface Nomad Client uses for allocations. |

**If not using Tailscale**, override these to your physical interface (e.g., `eth0`).

### Consul Variables (`roles/consul/defaults/main.yml`)

| Variable | Default | Description |
| :--- | :--- | :--- |
| `consul_datacenter` | `kalmar` | The datacenter name. |
| `consul_server_enabled` | `true` | Set to `false` for client-only nodes. |
| `consul_retry_join_ips` | `["100.116.81.88"]` | List of IPs to join for clustering. |
| `consul_ui_enabled` | `true` | Enable the Consul Web UI. |

### Nomad Variables (`roles/nomad/defaults/main.yml`)

| Variable | Default | Description |
| :--- | :--- | :--- |
| `nomad_datacenter` | `kalmar` | The datacenter name. |
| `nomad_server_enabled` | `true` | Set to `false` for client-only nodes. |
| `nomad_client_enabled` | `true` | Set to `false` for server-only nodes. |
| `nomad_consul_address` | `127.0.0.1:8500` | Address of the local Consul agent. |

## Usage

### 1. Prerequisites
- **Control Node**: Ansible installed.
- **Target Nodes**:
    - **Linux (Ubuntu/Debian)**: Accessible via SSH, Python installed.
    - **macOS**: **Homebrew** must be installed. User should be able to run `sudo` if needed (though most tasks run as user).
- **Inventory**: An inventory file (e.g., `inventory.ini`) with your target IPs.
- (Optional) A Tailscale Auth Key if adding new nodes.

### 2. Running the Playbook

**Basic Run:**
```bash
ansible-playbook -i inventory.ini playbooks/site.yml
```

**With Tailscale Auth Key (for new nodes):**
```bash
ansible-playbook -i inventory.ini playbooks/site.yml --extra-vars "tailscale_auth_key=tskey-auth-..."
```

**Overriding Variables (e.g., changing interface):**
```bash
ansible-playbook -i inventory.ini playbooks/site.yml --extra-vars "nomad_network_interface=eth0 consul_bind_interface=eth0"
```

## OS Support

This setup supports:
- **Ubuntu/Debian Linux**: Uses `apt`, `systemd`, and official binaries.
- **macOS**: Uses **Homebrew** (`brew`) to install Consul, Nomad, and Tailscale. Services are managed via `brew services`. Paths are automatically adjusted to Homebrew defaults (e.g., `/opt/homebrew/etc/...`).
