job "sql-perf-grafana-datasource" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  group "sqlperf_ds_svc" {
    count = 1

    task "sqlperf_ds_dkr" {
      driver = "docker"

      config {
        image = "registry.service.consul/xcalar-qa/sql-perf-grafana-datasource:latest"
        force_pull = true

        port_map {
          http = 80
        }

        volumes = [
          "/netstore/qa/jenkins/SqlScaleTest:/netstore/qa/jenkins/SqlScaleTest",
          "/netstore/qa/sqlPerfCompare:/netstore/qa/sqlPerfCompare"
        ]
      }

      service {
        name = "sql-perf-grafana-datasource"
        port = "http"
        tags = ["urlprefix-sql-perf-grafana-datasource.service.consul:9999/"]

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
