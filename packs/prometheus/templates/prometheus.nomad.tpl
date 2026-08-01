job "prometheus" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "prometheus-group" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = 9090
        to     = 9090
      }
    }

    task "prometheus" {
      driver = "docker"

      config {
        image = "prom/prometheus:[[ var "prometheus_version" . ]]"
        ports = ["http"]
        args = [
          "--config.file=/etc/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--web.console.libraries=/usr/share/prometheus/console_libraries",
          "--web.console.templates=/usr/share/prometheus/consoles",
          "--web.external-url=http://100.116.81.88/prometheus",
          "--web.route-prefix=/prometheus",
        ]

        # world-readable client-cert copies; don't chmod the originals (gotcha 8)
        volumes = ["[[ var "certs_dir" . ]]:/etc/prometheus/certs:ro"]

        mount {
          type   = "bind"
          source = "local/prometheus.yml"
          target = "/etc/prometheus/prometheus.yml"
        }
        mount {
          type   = "bind"
          source = "local/alerts"
          target = "/etc/prometheus/alerts"
        }
        mount {
          type   = "volume"
          source = "[[ var "data_volume" . ]]"
          target = "/prometheus"
        }
      }

      template {
        destination = "local/prometheus.yml"
        change_mode = "restart"
        data        = <<EOH
global:
  scrape_interval: '30s'
  evaluation_interval: '30s'

rule_files:
  - '/etc/prometheus/alerts/*.yml'

scrape_configs:
  # Self-scrape. Prometheus runs with --web.route-prefix=/prometheus, so its
  # metrics endpoint is at /prometheus/metrics, not /metrics.
  - job_name: 'prometheus'
    metrics_path: '/prometheus/metrics'
    static_configs:
      - targets: ['localhost:9090']

  # Nomad — HTTPS with client cert. Requires `telemetry { prometheus_metrics =
  # true }` in nomad.hcl (set by the nomad-tls role). The ?format=prometheus
  # query param switches /v1/metrics from JSON to Prometheus text format.
  - job_name: 'nomad'
    scheme: https
    metrics_path: '/v1/metrics'
    params:
      format: ['prometheus']
    tls_config:
      ca_file:   /etc/prometheus/certs/nomad-ca.pem
      cert_file: /etc/prometheus/certs/nomad-client.pem
      key_file:  /etc/prometheus/certs/nomad-client-key.pem
    static_configs:
      - targets: ['100.116.81.88:4646']

  # Consul — HTTP API is now 127.0.0.1-only, so scrape via HTTPS :8501.
  # Requires `telemetry { prometheus_retention_time = "..." }` in consul.hcl.
  - job_name: 'consul'
    scheme: https
    metrics_path: '/v1/agent/metrics'
    params:
      format: ['prometheus']
    tls_config:
      ca_file:   /etc/prometheus/certs/consul-ca.pem
      cert_file: /etc/prometheus/certs/consul-client.pem
      key_file:  /etc/prometheus/certs/consul-client-key.pem
    static_configs:
      - targets: ['100.116.81.88:8501']

  # Node Exporter discovered via Consul service catalog.
  - job_name: 'node-exporter'
    consul_sd_configs:
      - server: '100.116.81.88:8501'
        scheme: https
        tls_config:
          ca_file:   /etc/prometheus/certs/consul-ca.pem
          cert_file: /etc/prometheus/certs/consul-client.pem
          key_file:  /etc/prometheus/certs/consul-client-key.pem
        services: ['node-exporter']
    relabel_configs:
      - source_labels: ['__meta_consul_node']
        target_label: 'instance'

  # Other Consul-registered services that opt in by tagging with "metrics".
  # Most app containers don't expose /metrics so we only scrape ones that
  # explicitly advertise the "metrics" tag in their service registration.
  - job_name: 'consul-services'
    consul_sd_configs:
      - server: '100.116.81.88:8501'
        scheme: https
        tls_config:
          ca_file:   /etc/prometheus/certs/consul-ca.pem
          cert_file: /etc/prometheus/certs/consul-client.pem
          key_file:  /etc/prometheus/certs/consul-client-key.pem
    relabel_configs:
      # Drop anything that doesn't have a "metrics" tag.
      - source_labels: ['__meta_consul_tags']
        regex: '.*,metrics,.*'
        action: keep
      - source_labels: ['__meta_consul_service']
        target_label: 'service'
      - source_labels: ['__meta_consul_node']
        target_label: 'node'
EOH
      }

      # {{ $labels.* }} below is Prometheus templating, which collides with
      # consul-template's default delimiters — shift consul-template to
      # triple braces so the alert annotations pass through untouched.
      template {
        destination     = "local/alerts/homelab.yml"
        change_mode     = "restart"
        left_delimiter  = "{{{"
        right_delimiter = "}}}"
        data            = <<EOH
groups:
  - name: homelab
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.job }} is down"
          description: "{{ $labels.instance }} has been down for more than 2 minutes."

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85% for 5 minutes."

      - alert: HighCPUUsage
        expr: 100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space below 15%"

      - alert: NomadJobFailed
        expr: nomad_nomad_job_summary_failed > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Nomad job {{ $labels.job }} has failed allocations"
EOH
      }

      resources {
        cpu        = 300
        memory     = 256
        memory_max = 512
      }

      service {
        name = "prometheus"
        port = "http"
        tags = [[ var "service_tags" . | toStringList ]]

        check {
          name     = "alive"
          type     = "http"
          path     = "/prometheus/-/healthy"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }
  }
}
