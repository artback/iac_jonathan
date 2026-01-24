# IAC Jonathan Project

This project contains Infrastructure as Code (IaC) configurations.

## Modules

### Postgres

The `postgres` module provides a Nomad job definition for deploying a PostgreSQL container.
For more details, refer to the [Postgres README](postgres/README.md).

## Setup and Usage

(Add general setup and usage instructions for the entire project here)
# How to Use

## Ansible

1.  Navigate to the `ansible` directory.
2.  Update `playbooks/site.yml` or create a new inventory file with your target IPs.
3.  Run:
    ```bash
    ansible-playbook -i inventory.ini playbooks/site.yml
    ```

## Terraform

1.  Navigate to `terraform/modules/nomad_cluster_aws`.
2.  Initialize Terraform:
    ```bash
    terraform init
    ```
3.  Create a `terraform.tfvars` file or pass variables via command line.
    ```hcl
    ssh_key_name = "my-aws-key"
    ```
4.  Apply:
    ```bash
    terraform apply
    ```
5.  Use the output IPs to populate your Ansible inventory.

### Dependencies
- Terraform >= 1.0
- Ansible >= 2.9
