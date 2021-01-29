job "coverage-grafana-datasource" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  group "cvg_ds_svc" {
    count = 1

    task "cvg_ds_dkr" {
      driver = "docker"

      config {
        image = "registry.service.consul/xcalar-qa/coverage-grafana-datasource:latest"
        force_pull = true

        port_map {
          http = 80
        }

        volumes = [
          "/netstore/qa/coverage:/netstore/qa/coverage"
        ]
      }

      service {
        name = "coverage-grafana-datasource"
        port = "http"
        tags = ["urlprefix-coverage-grafana-datasource.service.consul:9999/"]

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
