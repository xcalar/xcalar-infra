job "petname" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  constraint {
    attribute = "${meta.cluster}"
    value     = "newton"
  }

  update {
    max_parallel      = 1
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "10m"
    auto_revert       = false
    canary            = 0
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  group "petname" {
    count = 1

    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    task "petname" {
      driver = "docker"

      config {
        image      = "registry.service.consul/xcalar/petname:latest"
        force_pull = true

        port_map {
          http = 2015
        }
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 50  # 256MB

        network {
          port "http" {}
        }
      }

      service {
        name = "petname"
        tags = ["urlprefix-petname.service.consul:443/", "urlprefix-petname.nomad:9999/", "urlprefix-petname.service.consul:9999/"]
        port = "http"

        check {
          name     = "petname is alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
