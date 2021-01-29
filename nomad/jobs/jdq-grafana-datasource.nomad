job "jdq-grafana-datasource" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  group "jdq_ds_svc" {
    count = 1

    task "jdq_ds_dkr" {
      driver = "docker"

      config {
        image = "registry.service.consul/xcalar-qa/jdq-grafana-datasource:latest"
        force_pull = true

        port_map {
          http = 80
        }
      }

      service {
        name = "jdq-grafana-datasource"
        port = "http"
        tags = ["urlprefix-jdq-grafana-datasource.service.consul:9999/"]

        check {
          name     = "alive"
          type     = "http"
          path     = "/"
          interval = "60s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 500 # 500MHz
        memory = 200 # 200MB
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
