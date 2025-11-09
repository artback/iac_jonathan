# This job file defines a PostgreSQL service in Nomad.
job "${var.job_name}" {
  # Specifies the datacenters where the job can run.
  datacenters = ["${var.datacenter}"]
  # The type of job, "service" means it's a long-running service.
  type = "service"

  # A group defines a set of tasks that should be co-located on the same client.
  group "${var.group_name}" {
    # The number of instances of this group to run.
    count = 1

    # Defines a host volume to persist PostgreSQL data.
    # Using a variable for the Host Volume source
    volume "${var.volume_id}" {
      type      = "host"
      source    = "${var.host_volume_name}"
      read_only = false
    }

    # Configures the network for the group.
    network {
      # Defines a port named "db".
      port "db" {
        # Assigns a static port from a variable.
        static = var.db_port
      }
    }

    # Defines the main task to run, which is the PostgreSQL container.
    task "postgres" {
      # The driver to use for running the task, in this case, "docker".
      driver = "docker"

      # Configuration for the Docker driver.
      config {
        # The Docker image to use.
        image = "postgres:${var.pg_version}-alpine"
        # Maps the "db" port to the container.
        ports = ["db"]
      }

      # Sets environment variables for the container.
      env {
        POSTGRES_PASSWORD = "${var.pg_password}" # Best practice is to use Nomad Secrets/Vault for this
        POSTGRES_DB = "${var.pg_db_name}"
      }

      # Mounts the host volume into the container.
      volume_mount {
        volume      = "${var.volume_id}"
        destination = "/var/lib/postgresql/data"
        read_only   = false
      }
    }
  }
}