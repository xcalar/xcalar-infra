job "promtail" {
  datacenters = ["xcalar-sjc"]
  type        = "system"

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    auto_revert      = false
    canary           = 0
  }

  group "promtail" {
    count = 1

    restart {
      attempts = 10
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    task "promtail" {
      driver = "docker"

      config {
        image      = "grafana/promtail:master"
        volumes    = ["/var/log:/var/log", "local/config.yaml:/etc/promtail/config.yaml"]
        force_pull = true

        #args    = ["-config.file=/etc/promtail/docker-config.yaml"]
        args = ["-config.file=/etc/promtail/config.yaml"]
      }

      resources {
        network {
          port "http" {
            static = "9080"
          }
        }

        cpu    = 1800
        memory = 32
      }

      template {
        data = <<EOT
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

client:
  url: http://loki-ui.service.consul:3100/api/prom/push

scrape_configs:
- job_name: system
  entry_parser: raw
  static_configs:
  - targets:
      - localhost
    labels:
      job: varlogs
      __path__: /var/log/*log
EOT

        change_mode = "restart"
        destination = "local/config.yaml"
      }
    }
  }
}
