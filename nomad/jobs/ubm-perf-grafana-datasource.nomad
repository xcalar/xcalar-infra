job "ubm-perf-grafana-datasource" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  group "ubmperf_ds_svc" {
    count = 1

    task "ubmperf_ds_dkr" {
      driver = "docker"

      config {
        image = "registry.service.consul/xcalar-qa/ubm-perf-grafana-datasource:latest"
        force_pull = true

        port_map {
          http = 80
        }
      }

      service {
        name = "ubm-perf-grafana-datasource"
        port = "http"
        tags = ["urlprefix-ubm-perf-grafana-datasource.service.consul:9999/"]

        check {
          name     = "alive"
          type     = "http"
          path     = "/"
          interval = "60s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 1000 # MHz
        memory = 1024 # MB
        network {
          port "http" {}
        }
      }

      logs {
        max_file_size = 15
      }

      kill_timeout = "120s"
    }
  }
}
